defmodule Xbase.Types do
  @moduledoc """
  Data structures for DBF file format components.
  """

  defmodule Header do
    @moduledoc """
    DBF file header structure containing metadata about the database file.
    
    The header is a 32-byte structure at the beginning of every DBF file.
    """
    
    defstruct [
      :version,           # File type flag (dBase version)
      :last_update_year,  # Year of last update (0-99, add 1900)
      :last_update_month, # Month of last update (1-12)
      :last_update_day,   # Day of last update (1-31)
      :record_count,      # Number of records in file
      :header_length,     # Number of bytes in header
      :record_length,     # Number of bytes in record
      :transaction_flag,  # Transaction flag
      :encryption_flag,   # Encryption flag
      :mdx_flag,         # MDX flag
      :language_driver   # Language driver ID
    ]

    @type t :: %__MODULE__{
      version: integer(),
      last_update_year: integer(),
      last_update_month: integer(),
      last_update_day: integer(),
      record_count: non_neg_integer(),
      header_length: pos_integer(),
      record_length: pos_integer(),
      transaction_flag: integer(),
      encryption_flag: integer(),
      mdx_flag: integer(),
      language_driver: integer()
    }
  end

  defmodule FieldDescriptor do
    @moduledoc """
    DBF field descriptor structure defining individual field properties.
    
    Each field descriptor is a 32-byte structure describing one field in the database.
    """
    
    defstruct [
      :name,              # Field name (11 bytes, null-terminated)
      :type,              # Field type (C, N, D, L, M, etc.)
      :length,            # Field length in bytes
      :decimal_count,     # Number of decimal places for numeric fields
      :work_area_id,      # Work area ID
      :set_fields_flag,   # SET FIELDS flag
      :index_field_flag   # Index field flag
    ]

    @type t :: %__MODULE__{
      name: String.t(),
      type: String.t(),
      length: pos_integer(),
      decimal_count: non_neg_integer(),
      work_area_id: integer(),
      set_fields_flag: integer(),
      index_field_flag: integer()
    }
  end

  defmodule Record do
    @moduledoc """
    DBF record structure containing parsed field data and metadata.
    
    Represents a single record from a DBF file with parsed field values,
    deletion status, and raw binary data for debugging purposes.
    """
    
    defstruct [
      :data,      # Map of field_name => parsed_value
      :deleted,   # Boolean indicating if record is deleted
      :raw_data   # Original binary data for debugging
    ]

    @type t :: %__MODULE__{
      data: %{String.t() => any()},
      deleted: boolean(),
      raw_data: binary()
    }
  end
end