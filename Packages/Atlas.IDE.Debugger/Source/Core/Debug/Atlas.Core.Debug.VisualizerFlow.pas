unit Atlas.Core.Debug.VisualizerFlow;

// Entscheidungen der Debug-Visualisierer (#835) außerhalb von Erkennung und Text, ohne IDE prüfbar (#1967): welche
// Arten ein Ansichtsfenster haben, Optionen aus den Einstellungen, wann neu angemeldet wird, wann eine Art greift
// und welcher Text in der Liste der IDE steht. Atlas.IDE.Debug.Visualizers meldet bei der IDE an und wertet aus.

interface

uses
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.VisualizerKinds,
  Atlas.Core.Debug.Visualizers;

type
  TAtlasVisualizerFlow = class
  public const
    /// <summary>Arten mit Ansichtsfenster; TGUID und Geometrie haben nur den Ersatztext.</summary>
    cViewerKinds = [TAtlasVisualizerKind.Lists, TAtlasVisualizerKind.Dictionaries, TAtlasVisualizerKind.DataSets,
      TAtlasVisualizerKind.Bytes, TAtlasVisualizerKind.Json, TAtlasVisualizerKind.Colors,
      TAtlasVisualizerKind.Graphics];
  public
    /// <summary>Hat AKind ein Ansichtsfenster?</summary>
    class function HasViewer(AKind: TAtlasVisualizerKind): Boolean; static;
    /// <summary>Optionen der Visualisierer aus ASettings.</summary>
    class function OptionsOf(const ASettings: TAtlasPluginSettings): TAtlasVisualizerOptions; static;
    /// <summary>Angemeldet wird je Art; nur Schalter und Arten verlangen eine neue Anmeldung, der Rest wird je Wert
    /// gelesen.</summary>
    class function Signature(const ASettings: TAtlasPluginSettings): string; static;
    /// <summary>Gestartet (AStarted) und Schalter oder Arten geändert: neu anmelden?</summary>
    class function NeedsReregister(AStarted: Boolean; const AOld, ANew: string): Boolean; static;
    /// <summary>Greift AKind: Visualisierer an (AEnabled) und die Art gewählt?</summary>
    class function Wants(AEnabled: Boolean; AKind: TAtlasVisualizerKind; const AKinds: TAtlasVisualizerKinds): Boolean;
      static;
    /// <summary>Text in der Liste der IDE: der eigene, sonst der der IDE ('' wäre ein leerer Wert).</summary>
    class function Shown(const AOwn, AEvalResult: string): string; static;
    /// <summary>Gehört AIndex zu ACount unterstützten Typen?</summary>
    class function ValidType(AIndex, ACount: Integer): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasVisualizerFlow }

class function TAtlasVisualizerFlow.HasViewer(AKind: TAtlasVisualizerKind): Boolean;
begin
  Result := AKind in cViewerKinds;
end;

class function TAtlasVisualizerFlow.OptionsOf(const ASettings: TAtlasPluginSettings): TAtlasVisualizerOptions;
begin
  Result := TAtlasVisualizerOptions.Defaults;
  Result.Kinds := TAtlasVisualizerSettings.ParseKinds(ASettings.DebugVisualizerTypes);
  Result.NameFields := TAtlasVisualizerSettings.ParseNameFields(ASettings.DebugVisualizerNameFields);
  Result.MaxLength := ASettings.DebugVisualizerMaxLength;
  Result.Evaluation := TAtlasVisualizerSettings.ParseEvaluation(ASettings.DebugVisualizerEvaluation);
  Result.MaxImagePixels := ASettings.DebugVisualizerMaxImagePixels;
end;

class function TAtlasVisualizerFlow.Signature(const ASettings: TAtlasPluginSettings): string;
begin
  Result := BoolToStr(ASettings.DebugVisualizers, True) + '|' + ASettings.DebugVisualizerTypes;
end;

class function TAtlasVisualizerFlow.NeedsReregister(AStarted: Boolean; const AOld, ANew: string): Boolean;
begin
  Result := AStarted and (AOld <> ANew);
end;

class function TAtlasVisualizerFlow.Wants(AEnabled: Boolean; AKind: TAtlasVisualizerKind;
  const AKinds: TAtlasVisualizerKinds): Boolean;
begin
  Result := AEnabled and (AKind in AKinds);
end;

class function TAtlasVisualizerFlow.Shown(const AOwn, AEvalResult: string): string;
begin
  Result := AOwn;
  if Result = '' then
  begin
    Result := AEvalResult;
  end;
end;

class function TAtlasVisualizerFlow.ValidType(AIndex, ACount: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex < ACount);
end;

end.
