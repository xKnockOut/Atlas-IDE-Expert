unit Argus.Common.Product.Version;

// Platform-Feature "Product", Root: Name und Version des Servers.
// Wird u. a. für "serverInfo" in der Antwort auf "initialize" verwendet.

interface

type
  /// <summary>Name und Version von Argus.</summary>
  TProductVersion = record
  public const
    Name = 'Argus';
    Version = '0.1.0';
  end;

implementation

end.
