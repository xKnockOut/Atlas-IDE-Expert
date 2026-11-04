unit Atlas.IDE.Editor.GutterColumnState;

// Stand der Atlas-Spalte (#768): oberer Editor und Tipp-Pause, die
// Überschreibungen vom Server (atlas.server.overrideMarks, je Datei und
// Textstand gemerkt), die Glühbirne der Cursorzeile und die Probleme der
// Datei. Fragt den Server nur, wenn er ohnehin läuft, und nach einer
// Tipp-Pause; ist er beschäftigt oder weg, erst nach RetryMs wieder. Neue
// Antworten zeichnen den oberen Editor neu. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Editor.GutterColumn,
  Atlas.Core.Lsp.Session;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasGutterColumnSessionFunc = reference to function: TLspSession;

  TAtlasIdeGutterColumnState = class
  public const
    OverridesCommand = 'atlas.server.overrideMarks';
  private const
    QuietMs = 600;
    OverridesTimeoutMs = 800;
    ActionsTimeoutMs = 600;
    FixesTimeoutMs = 3000;
    RetryMs = 5000;
  private
    FSession: TAtlasGutterColumnSessionFunc;
    FOptions: TAtlasGutterColumnOptions;
    // Oberer Editor und Tipp-Pause.
    FFileName: string;
    FText: string;
    FCaretLine: Integer;
    FChangedAt: UInt64;
    FRetryAt: UInt64;
    // Überschreibungen vom Server.
    FFetchedFile: string;
    FFetchedText: string;
    FOverrides: TAtlasFileOverrides;
    // Glühbirne der Cursorzeile.
    FActionFile: string;
    FActionText: string;
    FActionLine: Integer;
    FActionAsked: Boolean;
    FActionFound: Boolean;
    // Probleme der Datei, neu gelesen bei neuer Version des Speichers.
    FProblemsFile: string;
    FProblemsVersion: Integer;
    FProblems: TArray<TAtlasProblem>;
    function Session: TLspSession;
    /// <summary>Merkt Datei, Text und Cursorzeile von AView; True, wenn sich etwas geändert hat.</summary>
    function Changed(const AView: IOTAEditView): Boolean;
    /// <summary>True nach der Tipp-Pause und außerhalb der Wartezeit nach einem Fehler.</summary>
    function Settled: Boolean;
    /// <summary>True, wenn die Glühbirne der Cursorzeile neu zu erfragen ist.</summary>
    function ActionDue: Boolean;
    procedure FetchOverrides(ASession: TLspSession);
    procedure FetchAction(ASession: TLspSession);
  public
    constructor Create(const ASession: TAtlasGutterColumnSessionFunc);
    /// <summary>True für Pascal-Quelltexte (.pas, .dpr, .dpk, .inc).</summary>
    class function IsSource(const AFileName: string): Boolean; static;
    /// <summary>Welche Arten die Spalte zeigt, aus den Einstellungen.</summary>
    procedure ReadOptions;
    /// <summary>Alles Gemerkte vergessen (Spalte aus).</summary>
    procedure Clear;
    /// <summary>Nach jedem Takt mit der obersten Ansicht: Änderungen merken, nach der Tipp-Pause den Server
    /// fragen.</summary>
    procedure Track(const AView: IOTAEditView);
    function ProblemsOf(const AFileName: string): TArray<TAtlasProblem>;
    /// <summary>Was die Spalte für Zeile ALine (0-basiert) zeigen kann; ALineText: Text der Zeile im Editor (nur
    /// mit AHasText).</summary>
    function LineOf(const AFileName: string; ALine: Integer; const ALineText: string; AHasText: Boolean;
      out AOverrides: TAtlasGutterOverrides): TAtlasGutterLine;
    /// <summary>Überschreibungen der Zeile ALine (0-basiert) aus der letzten Antwort.</summary>
    function OverridesAt(const AFileName: string; ALine: Integer; out AEntry: TAtlasGutterOverrides): Boolean;
    /// <summary>Methoden, die die Zeile überschreibt bzw. die sie überschreiben.</summary>
    function TargetsOf(const AFileName: string; ALine: Integer): TArray<TAtlasGutterTarget>;
    /// <summary>Korrekturen des Servers für AProblem; AError: Meldung, wenn der Server nicht antwortet.</summary>
    function Fixes(const AFileName: string; const AProblem: TAtlasProblem; out AError: string): TArray<TLspCodeAction>;
    property Options: TAtlasGutterColumnOptions read FOptions;
    /// <summary>Datei des oberen Editors.</summary>
    property FileName: string read FFileName;
  end;

implementation

uses
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  ToolsAPI.Editor,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Problems.Store,
  Atlas.Core.Editor.Recursion,
  Atlas.IDE.Problems.Controller,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorRefresh;

procedure InvalidateTop;
var
  mEditors: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mEditors) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mEditors);
  end;
end;

{ TAtlasIdeGutterColumnState }

constructor TAtlasIdeGutterColumnState.Create(const ASession: TAtlasGutterColumnSessionFunc);
begin
  inherited Create;
  FSession := ASession;
  FActionLine := -1;
  FCaretLine := -1;
  FProblemsVersion := -1;
  FOptions := TAtlasGutterColumnOptions.All;
end;

class function TAtlasIdeGutterColumnState.IsSource(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  mExtension := ExtractFileExt(AFileName);
  Result := SameText(mExtension, '.pas') or SameText(mExtension, '.dpr') or SameText(mExtension, '.dpk') or
    SameText(mExtension, '.inc');
end;

function TAtlasIdeGutterColumnState.Session: TLspSession;
begin
  Result := nil;
  if Assigned(FSession) then
  begin
    Result := FSession();
  end;
end;

procedure TAtlasIdeGutterColumnState.ReadOptions;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  FOptions.Problems := mSettings.GutterColumnProblems;
  FOptions.CodeActions := mSettings.GutterColumnCodeActions;
  FOptions.Overrides := mSettings.GutterColumnOverrides;
end;

procedure TAtlasIdeGutterColumnState.Clear;
begin
  FFetchedFile := '';
  FFetchedText := '';
  FOverrides := Default(TAtlasFileOverrides);
  FActionFile := '';
  FActionFound := False;
  FActionAsked := False;
  FProblemsFile := '';
  FProblems := nil;
  FFileName := '';
end;

function TAtlasIdeGutterColumnState.Changed(const AView: IOTAEditView): Boolean;
var
  mText: string;
begin
  mText := TAtlasEditorBuffer.Text(AView.Buffer);
  Result := not SameText(FFileName, AView.Buffer.FileName) or (FText <> mText) or
    (FCaretLine <> AView.CursorPos.Line - 1);
  if Result then
  begin
    FFileName := AView.Buffer.FileName;
    FText := mText;
    FCaretLine := AView.CursorPos.Line - 1;
    FChangedAt := TThread.GetTickCount64;
  end;
end;

function TAtlasIdeGutterColumnState.Settled: Boolean;
var
  mMoment: UInt64;
begin
  mMoment := TThread.GetTickCount64;
  Result := (mMoment - FChangedAt >= QuietMs) and (mMoment >= FRetryAt);
end;

function TAtlasIdeGutterColumnState.ActionDue: Boolean;
begin
  Result := not FActionAsked or not SameText(FActionFile, FFileName) or (FActionLine <> FCaretLine) or
    (FActionText <> TAtlasRecursionMarks.LineOf(FText, FCaretLine));
end;

procedure TAtlasIdeGutterColumnState.Track(const AView: IOTAEditView);
var
  mSession: TLspSession;
  mStore: TAtlasProblemStore;
begin
  if (AView = nil) or (AView.Buffer = nil) or not IsSource(AView.Buffer.FileName) then
  begin
    Exit;
  end;
  // Neue Diagnosen: neu zeichnen, damit die Symbole folgen.
  mStore := TAtlasProblemsController.Current;
  if (mStore <> nil) and SameText(FProblemsFile, AView.Buffer.FileName) and (mStore.Version <> FProblemsVersion) then
  begin
    InvalidateTop;
  end;
  if Changed(AView) or not Settled then
  begin
    Exit;
  end;
  mSession := Session;
  if mSession = nil then
  begin
    Exit;
  end;
  if FOptions.Overrides and not (SameText(FFetchedFile, FFileName) and (FFetchedText = FText)) then
  begin
    FetchOverrides(mSession);
  end;
  if FOptions.CodeActions and ActionDue then
  begin
    FetchAction(mSession);
  end;
end;

procedure TAtlasIdeGutterColumnState.FetchOverrides(ASession: TLspSession);
var
  mValues: TJSONArray;
  mArguments: string;
  mAnswer: TJSONValue;
begin
  mValues := TJSONArray.Create;
  try
    mValues.Add(TLspSession.PathToUri(FFileName));
    mArguments := mValues.ToJSON;
  finally
    mValues.Free;
  end;
  try
    ASession.Sync(FFileName, FText);
    mAnswer := ASession.RunCommand(OverridesCommand, mArguments, OverridesTimeoutMs);
  except
    on E: ELspClientError do
    begin
      // Server beschäftigt, weg oder zu alt (Befehl unbekannt): später noch einmal, ohne den Editor zu bremsen.
      FRetryAt := TThread.GetTickCount64 + RetryMs;
      Exit;
    end;
  end;
  try
    FOverrides := TAtlasFileOverrides.FromJson(mAnswer,
      function(AUri: string): string
      begin
        Result := TLspSession.UriToPath(AUri);
      end);
  finally
    mAnswer.Free;
  end;
  FFetchedFile := FFileName;
  FFetchedText := FText;
  InvalidateTop;
end;

procedure TAtlasIdeGutterColumnState.FetchAction(ASession: TLspSession);
var
  mLineText: string;
  mFound: TArray<TLspCodeAction>;
  mAction: TLspCodeAction;
  mHad: Boolean;
begin
  mLineText := TAtlasRecursionMarks.LineOf(FText, FCaretLine);
  mHad := FActionFound;
  FActionFile := FFileName;
  FActionLine := FCaretLine;
  FActionText := mLineText;
  FActionAsked := True;
  FActionFound := False;
  try
    ASession.Sync(FFileName, FText);
    mFound := ASession.CodeActions(FFileName, TLspRange.Create(FCaretLine, 0, FCaretLine, Length(mLineText)),
      ActionsTimeoutMs);
  except
    on E: ELspClientError do
    begin
      FRetryAt := TThread.GetTickCount64 + RetryMs;
      mFound := nil;
    end;
  end;
  for mAction in mFound do
  begin
    FActionFound := FActionFound or (mAction.Disabled = '');
  end;
  if mHad or FActionFound then
  begin
    InvalidateTop;
  end;
end;

function TAtlasIdeGutterColumnState.ProblemsOf(const AFileName: string): TArray<TAtlasProblem>;
var
  mStore: TAtlasProblemStore;
begin
  mStore := TAtlasProblemsController.Current;
  Result := nil;
  if mStore = nil then
  begin
    Exit;
  end;
  if not SameText(FProblemsFile, AFileName) or (FProblemsVersion <> mStore.Version) then
  begin
    FProblemsFile := AFileName;
    FProblemsVersion := mStore.Version;
    FProblems := mStore.ForFile(AFileName);
  end;
  Result := FProblems;
end;

function TAtlasIdeGutterColumnState.LineOf(const AFileName: string; ALine: Integer; const ALineText: string;
  AHasText: Boolean; out AOverrides: TAtlasGutterOverrides): TAtlasGutterLine;
begin
  Result := Default(TAtlasGutterLine);
  AOverrides := Default(TAtlasGutterOverrides);
  if FOptions.Problems then
  begin
    Result.Problem := TAtlasGutterColumn.ProblemSymbol(ProblemsOf(AFileName), ALine);
  end;
  if FOptions.CodeActions and FActionFound and (ALine = FActionLine) and SameText(AFileName, FActionFile) then
  begin
    Result.Action := not AHasText or TAtlasRecursionMarks.LineMatches(ALineText, FActionText);
  end;
  // Zeile seit dem Abruf geändert: Die Pfeile warten auf die nächste Antwort.
  if FOptions.Overrides and OverridesAt(AFileName, ALine, AOverrides) and
    (not AHasText or TAtlasRecursionMarks.LineMatches(ALineText, TAtlasRecursionMarks.LineOf(FFetchedText, ALine))) then
  begin
    Result.Overrides := Length(AOverrides.Overrides) > 0;
    Result.Overridden := Length(AOverrides.Overridden) > 0;
  end;
end;

function TAtlasIdeGutterColumnState.OverridesAt(const AFileName: string; ALine: Integer;
  out AEntry: TAtlasGutterOverrides): Boolean;
begin
  AEntry := Default(TAtlasGutterOverrides);
  Result := SameText(AFileName, FFetchedFile) and FOverrides.At(ALine, AEntry);
end;

function TAtlasIdeGutterColumnState.TargetsOf(const AFileName: string; ALine: Integer): TArray<TAtlasGutterTarget>;
var
  mEntry: TAtlasGutterOverrides;
begin
  Result := nil;
  if OverridesAt(AFileName, ALine, mEntry) then
  begin
    Result := mEntry.Overrides + mEntry.Overridden;
  end;
end;

function TAtlasIdeGutterColumnState.Fixes(const AFileName: string; const AProblem: TAtlasProblem;
  out AError: string): TArray<TLspCodeAction>;
var
  mSession: TLspSession;
begin
  Result := nil;
  AError := '';
  mSession := Session;
  if mSession = nil then
  begin
    Exit;
  end;
  try
    mSession.Sync(FFileName, FText);
    Result := mSession.CodeActions(AFileName, TLspRange.Create(AProblem.StartLine, AProblem.StartCharacter,
      AProblem.EndLine, AProblem.EndCharacter), FixesTimeoutMs);
  except
    on E: ELspClientError do
    begin
      Result := nil;
      AError := E.Message;
    end;
  end;
end;

end.
