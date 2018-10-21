defmodule StubbexWeb.Router do
  use StubbexWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", StubbexWeb do
    pipe_through :browser # Use the default browser stack

    get "/", PageController, :index
  end

  scope "/stubs", StubbexWeb do
    pipe_through :api

    match :*, "/*any", StubController, :stub
  end
end
