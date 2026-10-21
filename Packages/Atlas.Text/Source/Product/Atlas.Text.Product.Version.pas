unit Atlas.Text.Product.Version;

// Eine Versionsangabe für Server, Plugin und Installer (ADR 0012).
// Tools/Set-Version.ps1 schreibt nur hier, Tools/Check-Version.ps1 liest hier;
// Atlas.Common.Product.Version und Atlas.Core.Product.Version verweisen auf
// diese Konstante.

interface

type
  /// <summary>Version von Atlas (SemVer).</summary>
  TAtlasVersion = record
  public const
    Version = '1.0.0';
  end;

implementation

end.
