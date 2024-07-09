# Gems

These gemfiles list specific configurations of gems that we use in testing.

## Test Matrix

- See [.github/workflows/test.yml](.github/workflows/test.yml) for the matrix of gemfiles that are tested.


Using a gemfile controls the specific versions of the gems that are installed, and can be used to reproduce customer configurations for testing.

## Local Testing

To install the gems specified by a specific gemfile:

```
BUNDLE_GEMFILE=gems/rails5.gemfile bundle install
```

Then, to run tests using these gems:

```
BUNDLE_GEMFILE=gems/rails5.gemfile bundle exec rake
```
