defmodule StubbexWeb.Router do
  use StubbexWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", StubbexWeb do
    # Use the default browser stack
    pipe_through :browser

    get "/", PageController, :index
  end

  scope "/stubs", StubbexWeb do
    match :*, "/*any", StubController, :stub
  end
end
