unit Atlas.UI.Analysis.FormLayout;

// Maße der Eingabedialoge des Moduls Analyse (Rolle-Unit anlegen, Symbolpfad): links eine Spalte für die
// Beschriftungen, rechts die Eingabefelder. Alle Werte in logischen Pixeln (96 dpi), umgerechnet über
// TAtlasScaling; nur die Breite der Eingabefelder hängt vom Dialog ab.

interface

type
  /// <summary>Abstände eines Eingabedialogs in Gerätepixeln.</summary>
  TAtlasFormLayout = record
  public const
    /// <summary>Rand des Dialogs, Breite der Beschriftungsspalte und Abstand zweier Zeilen bei 96 dpi.</summary>
    cGap = 12;
    cLabelWidth = 130;
    cSpacing = 8;
    /// <summary>Beschriftung so weit unter der Oberkante ihres Eingabefelds, dass die Texte auf einer Linie
    /// stehen (96 dpi).</summary>
    cLabelOffset = 3;
  public
    Gap: Integer;
    LabelWidth: Integer;
    EditWidth: Integer;
    /// <summary>Abstand zwischen zwei Zeilen.</summary>
    Spacing: Integer;
    LabelOffset: Integer;
    /// <summary>Maße für APpi; AEditWidth in logischen Pixeln.</summary>
    class function Create(AEditWidth, APpi: Integer): TAtlasFormLayout; static;
    /// <summary>Linke Kante der Eingabefelder.</summary>
    function FieldLeft: Integer;
    /// <summary>Innenbreite des Dialogs: Rand, Beschriftung, Eingabefeld, Rand.</summary>
    function ClientWidth: Integer;
  end;

implementation

uses
  Atlas.Plugin.Style.Scaling;

{ TAtlasFormLayout }

class function TAtlasFormLayout.Create(AEditWidth, APpi: Integer): TAtlasFormLayout;
begin
  Result.Gap := TAtlasScaling.ToDevice(cGap, APpi);
  Result.LabelWidth := TAtlasScaling.ToDevice(cLabelWidth, APpi);
  Result.EditWidth := TAtlasScaling.ToDevice(AEditWidth, APpi);
  Result.Spacing := TAtlasScaling.ToDevice(cSpacing, APpi);
  Result.LabelOffset := TAtlasScaling.ToDevice(cLabelOffset, APpi);
end;

function TAtlasFormLayout.FieldLeft: Integer;
begin
  Result := Gap + LabelWidth;
end;

function TAtlasFormLayout.ClientWidth: Integer;
begin
  Result := 2 * Gap + LabelWidth + EditWidth;
end;

end.
