# Stubbex–stub any host, any endpoint

This is a stub server, like Mountebank or Wiremock. Its purpose is to
automatically record, save, and reply with responses from real endpoints
whenever you try to hit the stub endpoint. Essentially, it's a cache at
the granularity of every endpoint for any host.

What sets Stubbex apart (in my opinion) are three things:

## Concurrency

Stubbex is designed to be massively concurrent. It takes advantage of
Elixir, Phoenix Framework, and the Erlang system to handle concurrent
incoming requests efficiently. Note that, since this project is new, this
has not been tested yet and there are no benchmarks. But _in theory,_ you
should be able to start up a single Stubbex server and hit it from many
different tests and CI builds. It will automatically fetch, save, and
reply with responses.

## Request Precision

This means that Stubbex stores and responds to requests using _all
pertinent_ information contained in the requests, like the method (GET,
POST, etc.), URLs, query parameters, request headers if any, and request
body if any. You can get it to save and give you a response with complete
precision. So you can stub any number of different hosts, endpoints, and
specific requests.

## Automation by Default

Some stub servers require you to configure their proxy strategy, some
require a bit more hand-holding to record requests, and some require you
to manually feed them the requests and stub responses. Stubbex requires
no configuration and tries to 'do the right thing': call out to the real
endpoints only if it needs to, and replay existing stubs whenever it can.

If you want to set up stubs manually, you have to place
the stub files in the format that Stubbex expects, at the right location,
as explained below.

## Example

Suppose you want to stub the response from a JSON Placeholder URL,
https://jsonplaceholder.typicode.com/todos/1 . First, you start up
Stubbex:

```
~/src/stubbex $ mix deps.get # First time only
              $ export stubbex_cert_pem=/path/to/cert.pem # If it's not in /etc/ssl. (May be) needed for HTTPS requests
              $ export stubbex_timeout_ms=10000 # Optional, default is 10 minutes
              $ mix phx.server # Run the stub server
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
* That's it, now you have the stub URL. This makes it reasonably easy to
  configure real and test/QA/etc. endpoints.

Now, check the `~/src/stubbex/stubs` subdirectory. There's a new
directory structure and a stub file there. Take a look:

    ~/src/stubbex $ less stubs/https/jsonplaceholder.typicode.com/todos/1/505633AE90C4EEC795F044DC9BB3FE58.json
    {"response":{"status_code":200,"headers"...

The stub is stored in a predictable location
(`stubs/protocol/host/path.../hash.json`) and is pretty-printed for your
viewing pleasure!

## The Hash

Notice the file name of the stub, `505633AE....json`. That's an
MD5-encoded hash of the request details:

* Method (GET, POST, etc.)
* Headers
* Body

These three details uniquely identify any request _to a given endpoint._
Stubbex uses this hash to look up the correct response for any request,
and if it doesn't have it, it will fetch it and save it for next time.

This 'request-addressable' file name allows Stubbex to pick the correct
response stub for any call without having to open and parse the stub file
itself. It effectively uses the filesystem as an index data structure.

You might be screaming at me, 'Why MD5?! Why not SHA-1/256/etc.?' The
thing is, it just doesn't matter that much. This is not a security issue
right now. If it ever looks like one, I'll change the hash. Right now I'm
just using the simplest widely-available hash I can find, and that's MD5.

## Developer Workflow

To use Stubbex as part of your dev workflow, first you'll need a running
Stubbex instance. The easiest way to get it running is as shown above–but
you will need to install [Elixir](https://elixir-lang.org/) on your dev
machine. Alternatively, you might
[deploy](https://hexdocs.pm/phoenix/deployment.html#content) Stubbex to a
shared internal server (**WARNING:** by no means expose it to the outside
world!) and use that for development and testing across multiple
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

You can template response stub files and Stubbex will immediately pick up
changes to the stubs and start serving on-the-fly evaluated responses.
Templates are named like `hash.json.eex` (they are [Embedded
Elixir](https://hexdocs.pm/eex/EEx.html#module-tags) files) and can, for
now, contain valid Elixir language expressions (coming soon: bindings to
request parameters). If you have a template like
`stubs/https/jsonplaceholder.typicode.com/todos/1/E406D55E4DBB26C8050FCDC3D20B7CAA.json.eex`,
you can edit it with your favourite text editor and insert valid
expressions according to the rules of EEx. For example, the above stub by
default has a body like this:

```
"body": "{\n  \"userId\": 1,\n  \"id\": 1,\n  \"title\": \"delectus aut autem\",\n  \"completed\": false\n}"
```

You can set it to be automatically completed if we're past 2017:

```
"body": "{\n  \"userId\": 1,\n  \"id\": 1,\n  \"title\": \"delectus aut autem\",\n  \"completed\": <%= DateTime.utc_now().year > 2017 %>\n}"
```

Then if you get the response again (with the `curl` command in
[Example]), you'll see that the `completed` attribute is set to `true`
(assuming your year is past 2017).

There are many other useful data manipulation functions in the [Elixir
standard library](https://hexdocs.pm/elixir/api-reference.html#content),
which can all be used as part of the EEx templates. This is of course in
addition to all the normal language features you'd expect from a
language, like arithmetic, looping and branching logic, etc.

You may be thinking, how should you get a stub in the first place, to
start editing? Simple! Let Stubbex record it for you by first hitting a
real endpoint. Then add the `.eex` file extension to the stub JSON file
and insert whatever template markup you need.

## Limitations

* No tests right now
* No documentation right now (other than the above)
* No benchmarks right now
* Can't configure where to save the stubs right now

That said, for testing run-of-the-mill REST APIs with JSON responses,
Stubbex is very helpful, even just running on your dev machine.
