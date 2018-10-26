[
  inputs:  ["mix.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: [
    get: :*,
    match: :*,
    pipe_through: :*,
    plug: :*,
    post: :*,
    put: :*
  ]
]
