unit BDLsp.Common.Product.Version;

// Platform-Feature "Product", Root: Name und Version des Servers.
// Wird u. a. für "serverInfo" in der Antwort auf "initialize" verwendet.

interface

type
  /// <summary>Name und Version von BetterDelphiLSP.</summary>
  TProductVersion = record
  public const
    Name = 'BetterDelphiLSP';
    Version = '0.1.0';
  end;

implementation

end.
