unit Atlas.IDE.SymbolPath.Service;

// Weg zwischen Symbolen (#1117) in der IDE:
// - ShowDialog öffnet den Eingabedialog (Menü Atlas › Weg zwischen Symbolen …,
//   Befehlspalette Atlas.SymbolPath), ShowDialogFrom mit vorbelegtem „Von“
//   (Kontextmenü „Weg von hier nach …“ mit dem qualifizierten Namen am
//   Cursor). Die letzte Eingabe bleibt für den nächsten Aufruf stehen.
// - Vorschläge im Dialog aus der Symbolsuche des Servers (workspace/symbol
//   mit kurzem Zeitlimit, wie „Symbol suchen“), als „Container.Name“.
// - Die Suche geht als Befehl atlas.symbolPath für das aktive Projekt im
//   Hintergrund an den Server (ARun wie beim Fenster „Atlas-Architektur“);
//   die Antwort liest TAtlasSymbolPathAnswer noch im Hintergrund, gezeigt wird
//   im Hauptthread im Ergebnisfenster als gezeichnete Kette. Eine ältere
//   Antwort nach einer neueren Anfrage fällt weg.
// - „In Architekturkarte zeigen“ öffnet das Fenster „Atlas-Architektur“
//   (#1118) mit den Units des Wegs markiert.
// - navigation.symbolPath aus (oder die Absturzsicherung „Weg zwischen
//   Symbolen“): Enabled = False, Menü, Palette und Kontextmenü blenden den
//   Befehl aus; ein Aufruf tut nichts.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.UI.SymbolPath.Dialog,
  Atlas.IDE.Architecture.Service;

type
  TAtlasIdeSymbolPath = class
  private class var
    FRun: TAtlasArchitectureRun;
    FSessionOf: TFunc<TLspSession>;
    FLast: TAtlasSymbolPathRequestInput;
    /// <summary>Nummer der letzten Anfrage; ältere Antworten fallen weg.</summary>
    FRequest: Integer;
    FInstalled: Boolean;
  private
    class procedure Search(const AInput: TAtlasSymbolPathRequestInput); static;
    class function Suggestions(const APattern: string): TArray<string>; static;
  public
    /// <summary>ARun: Befehl im Hintergrund; ASessionOf: laufende Sitzung für die Vorschläge oder nil.</summary>
    class procedure Install(const ARun: TAtlasArchitectureRun; const ASessionOf: TFunc<TLspSession>); static;
    class procedure Uninstall; static;
    /// <summary>navigation.symbolPath an und die Sicherung nicht ausgelöst.</summary>
    class function Enabled: Boolean; static;
    class procedure ShowDialog; static;
    /// <summary>Dialog mit „Von“ = AFrom; der Fokus steht in „Nach“.</summary>
    class procedure ShowDialogFrom(const AFrom: string); static;
  end;

implementation

uses
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Lsp.Client,
  Atlas.Core.SymbolPath.Model,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.ResultsWindow;

const
  /// <summary>Der Server bricht nach vier Fünfteln von requestTimeoutMs selbst ab; das hier ist nur die Grenze
  /// für eine hängende Verbindung.</summary>
  TimeoutMs = 120000;
  /// <summary>Beim Tippen: lieber keine Vorschläge als die IDE aufhalten.</summary>
  SuggestTimeoutMs = 1500;

{ TAtlasIdeSymbolPath }

class procedure TAtlasIdeSymbolPath.Install(const ARun: TAtlasArchitectureRun;
  const ASessionOf: TFunc<TLspSession>);
begin
  FRun := ARun;
  FSessionOf := ASessionOf;
  FLast := Default(TAtlasSymbolPathRequestInput);
  FLast.MaxSteps := TAtlasSymbolPathCommands.DefaultSteps;
  FInstalled := True;
  TAtlasIdeResultsWindow.OnShowRoute :=
    procedure(const AUnits: TArray<string>)
    begin
      TAtlasGuard.Run(TAtlasFeature.SymbolPath,
        procedure
        begin
          TAtlasIdeArchitecture.ShowRoute(AUnits);
        end);
    end;
end;

class procedure TAtlasIdeSymbolPath.Uninstall;
begin
  // Antworten, die noch unterwegs sind, fallen weg.
  Inc(FRequest);
  FInstalled := False;
  FRun := nil;
  FSessionOf := nil;
  TAtlasIdeResultsWindow.OnShowRoute := nil;
end;

class function TAtlasIdeSymbolPath.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.SymbolPath and not TAtlasGuard.Disabled(TAtlasFeature.SymbolPath);
end;

class procedure TAtlasIdeSymbolPath.ShowDialog;
begin
  ShowDialogFrom(FLast.From);
end;

class function TAtlasIdeSymbolPath.Suggestions(const APattern: string): TArray<string>;
var
  Session: TLspSession;
  Symbols: TArray<TAtlasSymbol>;
  Symbol: TAtlasSymbol;
begin
  Result := nil;
  Session := nil;
  if Assigned(FSessionOf) then
    Session := FSessionOf();
  if Session = nil then
    Exit;
  try
    Symbols := Session.WorkspaceSymbols(APattern, SuggestTimeoutMs);
  except
    on ELspClientError do
      Symbols := nil;
  end;
  for Symbol in Symbols do
    Result := Result + [TAtlasSymbolPathCommands.QualifiedName(Symbol.Name, Symbol.Container)];
end;

class procedure TAtlasIdeSymbolPath.ShowDialogFrom(const AFrom: string);
var
  Input: TAtlasSymbolPathRequestInput;
  Suggest: TAtlasSymbolPathSuggest;
begin
  if not FInstalled or not Enabled then
    Exit;
  Input := FLast;
  Input.From := AFrom;
  Suggest :=
    function(const APattern: string): TArray<string>
    begin
      Result := Suggestions(APattern);
    end;
  if not TAtlasSymbolPathDialog.Execute(Suggest, Input) then
    Exit;
  FLast := Input;
  Search(Input);
end;

class procedure TAtlasIdeSymbolPath.Search(const AInput: TAtlasSymbolPathRequestInput);
var
  Project: IOTAProject;
  Title: string;
  Request: Integer;
begin
  Title := TAtlasStrings.Fmt(TAtlasTextId.SymbolPathTitle, [AInput.From, AInput.To_]);
  Project := GetActiveProject;
  if (Project = nil) or (Project.FileName = '') then
  begin
    TAtlasIdeResultsWindow.ShowSymbolPathMessage(Title, TAtlasStrings.Text(TAtlasTextId.ArchitectureNoProject));
    Exit;
  end;
  Inc(FRequest);
  Request := FRequest;
  TAtlasIdeResultsWindow.ShowSymbolPathMessage(Title, TAtlasStrings.Fmt(TAtlasTextId.SymbolPathSearching,
    [AInput.From, AInput.To_]));
  if not Assigned(FRun) or not FRun(TAtlasSymbolPathCommands.Command,
    TAtlasSymbolPathCommands.Arguments(TLspSession.PathToUri(Project.FileName), AInput.From, AInput.To_,
      AInput.MaxSteps, AInput.All), TimeoutMs,
    procedure(AAnswer: string)
    var
      Answer: TAtlasSymbolPathAnswer;
      Parsed: Boolean;
    begin
      Parsed := TAtlasSymbolPathAnswer.Parse(AAnswer, Answer);
      TAtlasMainThread.Queue(TAtlasFeature.SymbolPath,
        procedure
        begin
          if not FInstalled or (Request <> FRequest) then
            Exit;
          if not Parsed then
            TAtlasIdeResultsWindow.ShowSymbolPathMessage(Title, TAtlasStrings.Text(TAtlasTextId.SymbolPathFailed))
          else if not Answer.Enabled then
            TAtlasIdeResultsWindow.ShowSymbolPathMessage(Title,
              TAtlasStrings.Text(TAtlasTextId.SymbolPathDisabled))
          else
            TAtlasIdeResultsWindow.ShowSymbolPath(Title, Answer, TAtlasIdeArchitecture.Enabled);
        end);
    end) then
    TAtlasIdeResultsWindow.ShowSymbolPathMessage(Title, TAtlasStrings.Text(TAtlasTextId.ArchitectureNoServer));
end;

end.
