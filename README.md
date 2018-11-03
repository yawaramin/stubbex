# Stubbex–stub and validate with ease

This is a stub server, like Mountebank or Wiremock. Its purpose is to
automatically save responses from real endpoints and use those going
forward whenever you try to hit the stub endpoint. It can also
interpolate responses from template stubs that you control, and validate
saved stubs against the real responses.

In other words, Stubbex sets up what Martin Fowler calls a
[self-initializing fake](https://martinfowler.com/bliki/SelfInitializingFake.html).

## Guide

* [Emphasis on Simplicity](#emphasis-on-simplicity)
* [Concurrency](#concurrency)
* [Request Precision](#request-precision)
* [Example](#example)
* [The Hash](#the-hash)
  * [The Stubbex Cookie and Scenarios](#the-stubbex-cookie-and-scenarios)
* [Developer Workflow](#developer-workflow)
  * [Editing Existing Stubs](#editing-existing-stubs)
  * [Stubbing Non-Existent Endpoints](#stubbing-non-existent-endpoints)
* [Templating the Response](#templating-the-response)
  * [Troubleshooting](#troubleshooting)
* [Validating the Stubs](#validating-the-stubs)
  * [JSON Schema Validation](#json-schema-validation)
* [Limitations](#limitations)

What sets Stubbex apart (in my opinion) are three things:

## Emphasis on Simplicity

The Stubbex philosophy is to do everything with as little configuration
as possible–typically zero config. Every stub server I've come across
requires a configuration file, or some HTTP commands, or a unit-test
framework, to tell it what to do.

Stubbex requires no configuration and tries to 'do the right thing':
call out to the real endpoints only if it needs to, and replay existing
stubs whenever it can. It can do validation of large subsets of stubs
with a single command.

If you want to set up stubs manually, you have to place the stub files
in the format that Stubbex expects, at the right location, as explained
below. However, you can also take advantage of Stubbex's initial
recording ability to edit already-existing stub files in place–even for
services that haven't been written yet.

## Concurrency

Stubbex is designed to be massively concurrent. It takes advantage of
Elixir, Phoenix Framework, and the Erlang system to handle concurrent
incoming requests efficiently. Note that, since this project is new,
this has not been tested yet and there are no benchmarks. But _in
theory,_ you should be able to start up a single Stubbex server and hit
it from many different tests and CI builds. It will automatically fetch,
save, and reply with responses.

Related to concurrency, another huge benefit that Stubbex brings to the
table (thanks to its implementation stack) is fault-tolerance. You can
send it bad inputs in a few different ways–and I discuss some of them in
the sections below–but what they all have in common is that, short of a
truly unforeseen catastrophic failure, Stubbex will recover from every
error and immediately be ready to handle the next request.

## Request Precision

This means that Stubbex stores and responds to requests using _all
pertinent_ information contained in the requests, like the method (GET,
POST, etc.), URLs, query parameters, request headers if any, and request
body if any. You can get it to save and give you a response with
complete precision. So you can stub any number of different hosts,
endpoints, and specific requests.

## Example

Suppose you want to stub the response from a JSON Placeholder URL,
https://jsonplaceholder.typicode.com/todos/1 . First, you start up
Stubbex:

```
~/src/stubbex $ mix deps.get # First time only
              $ # Optional config with defaults, see config/config.exs for details:
              $ export stubbex_cert_pem=/etc/ssl/cert.pem
              $ export stubbex_stubs_dir=.
              $ export stubbex_timeout_ms=600000
              $ # Run the stub server:
              $ mix phx.server
```

Then, send it a request:

```
~/src $ curl localhost:4000/stubs/https/jsonplaceholder.typicode.com/todos/1
{
  "userId": 1,
  "id": 1,
  "title": "delectus aut autem",
  "completed": false
}
```

Notice the completely mechanical translation from the real URL to the
stub URL. You can probably guess how it works:

* Prefix with `localhost:4000/stubs/`
* Remove the `:/`
* That's it, you now have the stub URL. This makes it pretty easy to
  configure real and test/QA/etc. endpoints.

Now, check the `~/src/stubbex/stubs` subdirectory. There's a new
directory structure and a stub file there. Take a look:

```
~/src/stubbex $ less stubs/https/jsonplaceholder.typicode.com/todos/1/E406D55E4DBB26C8050FCDC3D20B7CAA.json
{
  "response": {
    "status_code": 200,
    "headers": {...
```

The stub is stored in a predictable location
(`stubs/protocol/host/path.../hash.json`) and is pretty-printed for your
viewing pleasure.

## The Hash

Notice the file name of the stub, `E406D55E....json`. That's an MD5-
encoded hash of the request details:

* Method (GET, POST, etc.)
* URL
* Query parameters
* Headers
* Body

These five details uniquely identify any request, to any endpoint.
Stubbex uses this hash to look up the correct response for any request,
and if it doesn't have it, it will fetch it and save it for next time.

This 'request-addressable' file name allows Stubbex to pick the correct
response stub for any call without having to open and parse the stub
file itself. It effectively uses the filesystem as an index data
structure.

### The Stubbex Cookie and Scenarios

An implicit assumption here (indeed, Stubbex's basic assumption) is that
each _unique_ request has _exactly one_ response. So for example, a `GET
/cart` request should _always_ return the exact same response, for
example `{}`. But then what if the user adds an item to their cart? Most
real-world servers use some session-management mechanism, like a cookie,
to track the user's current state. Stubbex does the same thing; it sets
a `stubbex` cookie in every response that is exactly equal to the hash
of the request parameters.

And, if your app respects the `Set-Cookie` header and sends servers the
cookies they set (including the `stubbex` cookie), you can establish an
audit trail between every request and response. Here's an example of how
it would work:

```
Client: log in
Stubbex: response with cookie1 generated from log in request
C: get cart with cookie1 (i.e. a `Cookie: stubbex=cookie1` header
   because the client respects the server cookies)
S: response with cookie2 generated from get cart request with cookie1
C: add item to cart with cookie2
S: response with cookie3 generated from add item request with cookie2
C: get cart with cookie3
...
```

Effectively, you have a scenario (or a session) established by a chain
of `stubbex` cookies. No config and no special commands; just the
idiomatic HTTP state management mechanism. And, because Stubbex is an
immutable (well, at least in the same way that git is) store of
request-response pairs, you will deterministically get the exact same
response for every request with the right cookies–even for otherwise
identical requests like `GET /cart`.

## Developer Workflow

To use Stubbex as part of your dev workflow, first you'll need a running
Stubbex instance. The easiest way to get it running is as shown
above–but you will need to install [Elixir](https://elixir-lang.org/) on
your dev machine. Alternatively, you might
[deploy](https://hexdocs.pm/phoenix/deployment.html#content) Stubbex to
a shared internal server (**WARNING:** by no means expose it to the
outside world!) and use that for development and testing across multiple
developer machines and CI builds.

Next, set up a QA/test config in your app that points all the base URLs
for every service call to Stubbex, e.g.
`http://localhost:4000/stubs/http/...`. You would use your development
stack's normal configuration management system here. If you have a
serious networked app, you likely already have separate endpoints
configured for QA and PROD. In this case you'd just switch the QA
endpoints to the stubbed versions, as shown above.

Then, run your app with this QA config and let Stubbex automatically
capture and replay the stubs for you. The stubs will be available both
during iterative development and test suite runs as long as they use the
same QA config.

### Editing Existing Stubs

Stubbex caches all non-templated (i.e. static) stubs in memory for a
period of time (by default, ten minutes) to serve the response as fast
as possible. But you might like to edit an existing stub and immediately
see the changed response. So, Stubbex will automatically clear its cache
for a stub when you edit that stub. This helps with iterative
development.

Note that on Linux and the BSDs you'll need to install `inotify-tools`
to make instant edits work. See
https://hexdocs.pm/file_system/readme.html for more details.

### Stubbing Non-Existent Endpoints

Sometimes you'll need to stub out responses from endpoints that haven't
actually been written yet. Manually naming and placing the stub files in
the right directories would be a pain. Fortunately, Stubbex
automatically generates stub files for you _even for endpoints that
don't exist._ For example, you can send the following request:

```
curl localhost:4000/stubs/http/bla
```

Stubbex will try to get the response, see that it can't, and put a stub
file with the right name, in the right place, _with a 501 (not
implemented) status_ and an empty body:

```
~/src/stubbex $ less stubs/http/bla/FC4443CF188F5039AB8C6C96FC500EB9.json
{
  "response": {
    "status_code": 501,
    "headers": {},
    "body": ""
  },...
```

You can edit this stub, put in whatever response you need, and keep
going.

**WARNING:** don't use Postman or other browser-based tools to make
requests to Stubbex for the purpose of setting up stubs for later use.
They may add additional headers beyond your control, and Stubbex's
response matching is, as mentioned above, sensitive to exact request
headers. For example, see
https://github.com/postmanlabs/postman-app-support/issues/443 (a
five-year old issue wherein Postman sends additional headers in all
requests). If you want to set up stubs beforehand, you can:

* Hit Stubbex from your app (this is best)
* Use a tool like `curl` which sends requests exactly as you specify
* Write the stub files by hand (way less fun).

## Templating the Response

You can template response stub files and Stubbex will immediately pick
up changes to the stubs and start serving on-the-fly evaluated
responses. Templates are named like `hash.json.eex` (they are [Embedded
Elixir](https://hexdocs.pm/eex/EEx.html#module-tags) files) and can
contain any valid Elixir language expression as well as refer to request
parameters. If you have a template like
`stubs/https/jsonplaceholder.typicode.com/todos/1/E406D55E4DBB26C8050FCDC3D20B7CAA.json.eex`,
you can edit it with your favourite text editor and insert valid markup
according to the rules of EEx. For example, the above stub by default
has a body like this:

```
"body": "{\n  \"userId\": 1,\n  \"id\": 1,\n  \"title\": \"delectus aut autem\",\n  \"completed\": false\n}"
```

You can set the todo to be automatically completed if we're past 2017:

```
"body": "{\n  \"userId\": 1,\n  \"id\": 1,\n  \"title\": \"delectus aut autem\",\n  \"completed\": <%= DateTime.utc_now().year > 2017 %>\n}"
```

Or you can use the user-agent header as part of the todo title:

```
"body": "{\n  \"userId\": 1,\n  \"id\": 1,\n  \"title\": \"User agent: <%= headers["user-agent"] %>\",\n  \"completed\": false\n}"
```

Then if you get the response again (with the `curl` command in
[Example](#example)), you'll see that the `completed` attribute is set
to `true` (assuming your year is past 2017); or that the todo title is
`User agent: curl/7.54.0` (e.g.), or any other result, depending on
which markup you put in place.

Request parameters are available under the following names:

* `url`: string
* `query_string`: string
* `method`: string
* `headers`: map of string keys (header names) to string values; you can
  get values with `headers["header-name"]` (all lowercase) syntax
* `body`: string

There are many other useful data manipulation functions in the [Elixir
standard library](https://hexdocs.pm/elixir/api-reference.html#content),
which can all be used as part of the EEx templates. This is of course in
addition to all the normal features you'd expect from a language, like
arithmetic, looping and branching logic, etc. I recommend taking a look
at the Embedded Elixir link above; it has a five-minute crash course on
the template markup.

You may be thinking, how to get a stub in the first place, to start
editing? Simple! Let Stubbex record it for you by first hitting a real
(or fake!) endpoint. Then add the `.eex` file extension to the stub JSON
file and insert whatever markup you need.

Note that Stubbex doesn't cache template stub responses, because these
might change dynamically with every request (e.g., you might inject the
current time into the response).

### Troubleshooting

Be careful with putting markup in stubs. The templated stub is passed
through an interpolation engine (EEx), then decoded from a JSON-encoded
string into an Elixir-native data structure. If for example you miss
escaping the template stub's body JSON properly (see above for escaping
examples), you'll get runtime errors from Stubbex that look like this:

```
[error] GenServer "/stubs/https/jsonplaceholder.typicode.com/todos/1" terminating
** (Poison.SyntaxError) Unexpected token at position 1008: h
...
```

(`Poison` is the JSON decoder module).

In this case I forgot to escape the double-quotes around the body JSON
attributes, and Stubbex misinterpreted the result.

## Validating the Stubs

The trouble with static stubs is that they will get out of date. To
guard against this happening, one option is to make 'someone'
responsible for keeping the stub files up-to-date. Under [contract
testing](https://martinfowler.com/bliki/ContractTest.html), you might
actually also delegate some of the responsibility for stub upkeep for
each service's stubs to the corresponding service provider (obviously,
this only works if you can reach an agreement with the service
provider).

At the bare minimum, you would zip up each provider's stubs periodically
and 'throw it over the wall' and let them figure out if they're still
conforming to the request-response expectations. But this can be a tough
sell, so Stubbex provides a convenience to _validate_ stubs. For
example, to validate the stubs for the 'JSON Placeholder Todo ID 1'
endpoint we use above, you can send the following request:

```
~/src/stubbex $ curl localhost:4000/validations/https/jsonplaceholder.typicode.com/todos/1
```

And Stubbex replies with a colorized diff suitable for display in a
terminal:

<img width="1364" alt="Stubbex validation output" src="https://user-images.githubusercontent.com/6997/47684295-c28fe900-dba8-11e8-8f7f-3699d18a0111.png">

To validate _all_ the JSON Placeholder _todos,_ you can send:

```
~/src/stubbex $ curl localhost:4000/validations/https/jsonplaceholder.typicode.com/todos/
```

To validate _all_ the JSON Placeholder _stubs,_ you can send:

```
~/src/stubbex $ curl localhost:4000/validations/https/jsonplaceholder.typicode.com/
```

However, Stubbex doesn't support validating stubs at any higher level
and will error if you try. I think this is a reasonable balance if
you're trying to delegate validating stubs to service providers. They
would just worry about their own stubs.

*Tip:* when validating long responses, it's helpful to pipe the output
into `less -R`, because it can understand and show colours:

```
~/src/stubbex $ curl localhost:4000/validations/... | less -R
```

### JSON Schema Validation

Sometimes it isn't practical to validate the entire response body,
because a real server response will differ greatly between responses. In
these cases it's still valuable to know whether the _shape_ of the
response matches what you expect.

Stubbex allows you to validate the shape of the response by specifying
its [JSON Schema](http://json-schema.org/) in your stub. The workflow
would look very similar to the other Stubbex workflows: start by sending
a normal stub request from your app (which you may already have done),
then rename the `stubs/path/to/HASH.json` file to
`stubs/path/to/HASH.json.schema`. This will tell Stubbex to use JSON
schema validation for this stub. Then, put the response's expected JSON
Schema object in the stub's `response.body` field.

For example, here's an example schema for the todos we show above:

```
{
  "url": "https://jsonplaceholder.typicode.com/todos/1",
  "response": {
    ...,
    "body": {
      "$schema": "http://json-schema.org/draft-04/schema#",
      "title": "Todo",
      "description": "A reminder.",
      "type": "object",
      "properties": {
        "userId": {"type": "integer"},
        "id": {"type": "integer"},
        "title": {"type": "string"},
        "completed": {"type": "boolean"}
      },
      "required": ["userId", "id", "title", "completed"]
    }
  },
  ...
}
```

**Note:** due to the specific schema validation library that Stubbex
uses, the schemas must be versioned at Draft 4 at most.

Finally, to do an actual validation, run the usual validation command:

```
~/src/stubbex $ curl localhost:4000/validations/https/jsonplaceholder.typicode.com/todos/1
```

<img width="1383" alt="screen shot 2018-11-02 at 22 21 07" src="https://user-images.githubusercontent.com/6997/47947187-0f97f600-deee-11e8-9fe3-a84a4e59542b.png">

The response body is a green `:ok` to indicate that the schema
validation succeded.

Now, to simulate a validation error, try changing the `completed`
attribute type to `string`, and rerun the validation:

<img width="1384" alt="screen shot 2018-11-02 at 22 22 04" src="https://user-images.githubusercontent.com/6997/47947189-1e7ea880-deee-11e8-8bc8-697f1830b3c0.png">

The response body is a red description of the error and the path to the
erroring attribute.

## Limitations

* Not enough tests right now (run with `mix test.watch --stale` for
  continuous iterate-and-run cycle)
* No benchmarks right now

