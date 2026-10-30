unit Atlas.Text.Product.Version;

// Eine Versionsangabe für Server und Plugin (ADR 0012).
// Tools/Set-Version.ps1 schreibt nur hier, Tools/Check-Version.ps1 liest hier;
// Atlas.Common.Product.Version und Atlas.Core.Product.Version verweisen auf
// diese Konstante.

interface

type
  /// <summary>Version von Atlas (SemVer).</summary>
  TAtlasVersion = record
  public const
    Version = '1.2.0';
  end;

implementation

end.
