unit Atlas.Common.Product.Version;

// Platform-Feature "Product", Root: Name und Version des Servers.
// Wird u. a. für "serverInfo" in der Antwort auf "initialize" verwendet.
// Die Version steht nur in Atlas.Text.Product.Version (ADR 0012).

interface

uses
  Atlas.Text.Product.Version;

type
  /// <summary>Name und Version von Atlas.</summary>
  TProductVersion = record
  public const
    Name = 'Atlas';
    Version = TAtlasVersion.Version;
  end;

implementation

end.
