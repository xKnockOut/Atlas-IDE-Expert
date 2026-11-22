unit Atlas.Common.Semantics.ComponentRoots;

// Vorfahren der Komponenten und Steuerelemente der VCL und FMX: Wer davon abstammt, gehört einem Owner
// (Felder freigeben, Komponenten-Befehle) bzw. kann sich neu zeichnen (Setter mit Invalidate). Die
// Vorfahrenkette kommt vom Aufrufer (Unit und Index).

interface

const
  /// <summary>Komponenten-Wurzeln: Klassen, die einen Owner haben und ihre Kinder freigeben.</summary>
  cComponentRoots: array[0..13] of string = ('TComponent', 'TControl', 'TWinControl', 'TCustomControl',
    'TGraphicControl', 'TForm', 'TCustomForm', 'TFrame', 'TCustomFrame', 'TDataModule', 'TDataSet', 'TCustomPanel',
    'TPanel', 'TCustomConnection');
  /// <summary>Wurzeln der sichtbaren Steuerelemente.</summary>
  cControlRoots: array[0..9] of string = ('TControl', 'TWinControl', 'TCustomControl', 'TGraphicControl', 'TForm',
    'TCustomForm', 'TFrame', 'TCustomFrame', 'TCustomPanel', 'TPanel');

/// <summary>Kommt einer der Namen aus AChain in ARoots vor (ohne Groß- und Kleinschreibung)?</summary>
function DescendsFrom(const AChain: TArray<string>; const ARoots: array of string): Boolean;

implementation

uses
  System.StrUtils;

function DescendsFrom(const AChain: TArray<string>; const ARoots: array of string): Boolean;
var
  mName: string;
begin
  for mName in AChain do
  begin
    if MatchText(mName, ARoots) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

end.
