# Stubbex

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

    ~/src/stubbex $ mix deps.get # First time only
    ~/src/stubbex $ mix phx.server

Then, send it a request:

    ~/src $ curl localhost:4000/stubs/https/jsonplaceholder.typicode.com/todos/1
    {
      "userId": 1,
      "id": 1,
      "title": "delectus aut autem",
      "completed": false
    }

Notice the completely mechanical translation from the real URL to the
stub URL. You can probably guess how it works:

* Prefix with `localhost:4000/stubs/`
* Remove the `:/`
* That's it, now you have the stub URL. This makes it reasonably easy to
  configure real and test/QA/etc. endpoints.

Now, check the `~/src/stubbex/stubs` subdirectory. There's a new
directory structure and a stub file there. Take a look:

    ~/src/stubbex $ less stubs/https/jsonplaceholder.typicode.com/todos/1/505633AE90C4EEC795F044DC9BB3FE58
    {"response":{"status_code":200,"headers"...

The stub is stored in a predictable location
(`stubs/protocol/host/path.../hash`) in JSON format. You can use your
favourite JSON pretty-printing tool to view it.

## The Hash

Notice the file name of the stub, `505633AE...`. That's an MD5-encoded
hash of the request details:

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
just using the simplest hash I can find, and that's `erlang:md5`.

## Limitations

* No tests right now
* No documentation right now (other than the above)
* No benchmarks right now
* Stubbex can't handle chunked responses right now
* Can't configure where to save the stubs right now

That said, for testing run-of-the-mill REST APIs with JSON responses,
Stubbex should be very helpful, even just running on your dev machine.

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
