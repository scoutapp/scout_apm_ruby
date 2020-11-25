# Temporary Data

Use this directory for temporary test files.

## Usage

The `DATA_FILE_DIR` constant points at this directory:

```ruby
class MyTest < Minitest::Test
  def database_path
    File.expand_path('test.sqlite3', DATA_FILE_DIR)
  end

  # ... tests
end
```
