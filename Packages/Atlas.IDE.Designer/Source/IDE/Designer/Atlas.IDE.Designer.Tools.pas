unit Atlas.IDE.Designer.Tools;

// Eigene Knöpfe der Designer-Leiste für die größeren Designer-Funktionen
// (#605 ff.), an einer Stelle für TAtlasIdeDesignerCommands; jede Funktion
// hat einen eigenen Knopf und eine eigene Einstellung, damit sie nicht mit
// dem Menü „Anordnen“ kollidiert:
// - Abstände messen (#605, designer.measureDistances und
//   designer.measureAltKey, TAtlasIdeDesignerMeasure): Schalter.
// Nur im Hauptthread.

interface

uses
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Bar,
  Atlas.IDE.Designer.Measure;

type
  TAtlasIdeDesignerTools = class
  private
    FMeasure: TAtlasIdeDesignerMeasure;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Knöpfe nach den Einstellungen.</summary>
    function Buttons(const ASettings: TAtlasPluginSettings): TArray<TAtlasDesignerButton>;
    /// <summary>Klick auf den Knopf AId ohne Menü; False, wenn er nicht hierher gehört.</summary>
    function Run(const AId: string): Boolean;
    procedure ApplyTheme;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasIdeDesignerTools }

constructor TAtlasIdeDesignerTools.Create;
begin
  inherited Create;
  FMeasure := TAtlasIdeDesignerMeasure.Create;
end;

destructor TAtlasIdeDesignerTools.Destroy;
begin
  FMeasure.Free;
  inherited Destroy;
end;

function TAtlasIdeDesignerTools.Buttons(const ASettings: TAtlasPluginSettings): TArray<TAtlasDesignerButton>;
var
  mButton: TAtlasDesignerButton;
begin
  Result := nil;
  mButton := FMeasure.Button(ASettings);
  if mButton.Id <> '' then
  begin
    Result := Result + [mButton];
  end;
end;

function TAtlasIdeDesignerTools.Run(const AId: string): Boolean;
begin
  Result := True;
  if SameText(AId, TAtlasIdeDesignerMeasure.cId) then
  begin
    FMeasure.Toggle;
  end
  else
  begin
    Result := False;
  end;
end;

procedure TAtlasIdeDesignerTools.ApplyTheme;
begin
  FMeasure.ApplyTheme;
end;

end.
