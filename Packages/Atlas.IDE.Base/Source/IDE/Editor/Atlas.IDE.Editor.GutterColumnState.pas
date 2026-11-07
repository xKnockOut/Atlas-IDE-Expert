unit Atlas.IDE.Editor.GutterColumnState;

// Stand der Atlas-Spalte (#768): oberer Editor und Tipp-Pause, die
// Überschreibungen vom Server (atlas.server.overrideMarks, je Datei und
// Textstand gemerkt), die Glühbirne der Cursorzeile und die Probleme der
// Datei. Fragt den Server nur, wenn er ohnehin läuft, und nach einer
// Tipp-Pause; ist er beschäftigt oder weg, erst nach RetryMs wieder. Neue
// Antworten zeichnen den oberen Editor neu. Nur im Hauptthread.
// Überschreibungen und Glühbirne fragt eine Anfrage im Hintergrund
// (TAtlasBackgroundRequest), höchstens eine zugleich. Früher wartete der
// Hauptthread bis zu 800 ms; bei beschäftigtem Server kam keine Antwort an
// und die IDE hing bei jedem Zeilenwechsel (2.0-stable).

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Editor.GutterColumn,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.BackgroundRequest;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasGutterColumnSessionFunc = reference to function: TLspSession;

  /// <summary>Zuletzt erfragte Glühbirne: Datei, Zeile und Zeilentext der Frage und ob es eine Aktion gibt.</summary>
  TAtlasGutterActionAsk = record
    FileName: string;
    Text: string;
    Line: Integer;
    Asked: Boolean;
    Found: Boolean;
  end;

  TAtlasIdeGutterColumnState = class
  public const
    cOverridesCommand = 'atlas.server.overrideMarks';
  private const
    cQuietMs = 600;
    cOverridesTimeoutMs = 5000;
    cActionsTimeoutMs = 5000;
    cFixesTimeoutMs = 3000;
    cRetryMs = 5000;
  private
    FSession: TAtlasGutterColumnSessionFunc;
    FRequest: TAtlasBackgroundRequest;
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
    FAction: TAtlasGutterActionAsk;
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
    /// <summary>Was fehlt, beim Server erfragen: Überschreibungen, sonst die Glühbirne; eine Anfrage
    /// zugleich.</summary>
    procedure FetchDue(ASession: TLspSession);
    procedure FetchOverrides(ASession: TLspSession);
    /// <summary>Antwort auf FetchOverrides im Hauptthread; AOk = False: später neu versuchen.</summary>
    procedure OverridesFetched(AOk: Boolean; const AFileName, AText: string; const AOverrides: TAtlasFileOverrides);
    procedure FetchAction(ASession: TLspSession);
    /// <summary>Antwort auf FetchAction im Hauptthread; gilt nur, solange Datei, Zeile und Text gleich sind.</summary>
    procedure ActionFetched(AOk: Boolean; const AFileName, ALineText: string; ALine: Integer;
      const AFound: TArray<TLspCodeAction>);
  public
    constructor Create(const ASession: TAtlasGutterColumnSessionFunc);
    destructor Destroy; override;
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
  Atlas.Core.Diagnostics.Guard,
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
  FRequest := TAtlasBackgroundRequest.Create(TAtlasFeature.GutterColumn);
  FAction.Line := -1;
  FCaretLine := -1;
  FProblemsVersion := -1;
  FOptions := TAtlasGutterColumnOptions.All;
end;

destructor TAtlasIdeGutterColumnState.Destroy;
begin
  // Laufende Anfrage abwarten; ihre Antwort verfällt.
  FRequest.Free;
  inherited;
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
  FAction.FileName := '';
  FAction.Found := False;
  FAction.Asked := False;
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
  Result := (mMoment - FChangedAt >= cQuietMs) and (mMoment >= FRetryAt);
end;

function TAtlasIdeGutterColumnState.ActionDue: Boolean;
begin
  Result := not FAction.Asked or not SameText(FAction.FileName, FFileName) or (FAction.Line <> FCaretLine) or
    (FAction.Text <> TAtlasRecursionMarks.LineOf(FText, FCaretLine));
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
  if Changed(AView) or not Settled or FRequest.Busy then
  begin
    Exit;
  end;
  mSession := Session;
  if mSession = nil then
  begin
    Exit;
  end;
  FetchDue(mSession);
end;

procedure TAtlasIdeGutterColumnState.FetchDue(ASession: TLspSession);
begin
  if FOptions.Overrides and not (SameText(FFetchedFile, FFileName) and (FFetchedText = FText)) then
  begin
    FetchOverrides(ASession);
  end;
  // Eine Anfrage zugleich: die Glühbirne im nächsten Takt.
  if FOptions.CodeActions and ActionDue and not FRequest.Busy then
  begin
    FetchAction(ASession);
  end;
end;

procedure TAtlasIdeGutterColumnState.FetchOverrides(ASession: TLspSession);
var
  mValues: TJSONArray;
  mArguments, mFileName, mText: string;
  mOverrides: TAtlasFileOverrides;
begin
  mValues := TJSONArray.Create;
  try
    mValues.Add(TLspSession.PathToUri(FFileName));
    mArguments := mValues.ToJSON;
  finally
    mValues.Free;
  end;
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  ASession.Sync(FFileName, FText);
  mFileName := FFileName;
  mText := FText;
  mOverrides := Default(TAtlasFileOverrides);
  // Server beschäftigt, weg oder zu alt (Befehl unbekannt, AOk = False): später noch einmal.
  FRequest.Start(
    procedure
    var
      mAnswer: TJSONValue;
    begin
      mAnswer := ASession.RunCommand(cOverridesCommand, mArguments, cOverridesTimeoutMs);
      try
        mOverrides := TAtlasFileOverrides.FromJson(mAnswer,
          function(AUri: string): string
          begin
            Result := TLspSession.UriToPath(AUri);
          end);
      finally
        mAnswer.Free;
      end;
    end,
    procedure(AOk: Boolean; const AError: string)
    begin
      OverridesFetched(AOk, mFileName, mText, mOverrides);
    end);
end;

procedure TAtlasIdeGutterColumnState.OverridesFetched(AOk: Boolean; const AFileName, AText: string;
  const AOverrides: TAtlasFileOverrides);
begin
  if not AOk then
  begin
    FRetryAt := TThread.GetTickCount64 + cRetryMs;
    Exit;
  end;
  // Gilt für den gefragten Stand; ist der Text inzwischen anders, fragt Track neu.
  FOverrides := AOverrides;
  FFetchedFile := AFileName;
  FFetchedText := AText;
  InvalidateTop;
end;

procedure TAtlasIdeGutterColumnState.FetchAction(ASession: TLspSession);
var
  mLineText, mFileName: string;
  mLine: Integer;
  mFound: TArray<TLspCodeAction>;
begin
  mLineText := TAtlasRecursionMarks.LineOf(FText, FCaretLine);
  FAction.FileName := FFileName;
  FAction.Line := FCaretLine;
  FAction.Text := mLineText;
  FAction.Asked := True;
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  ASession.Sync(FFileName, FText);
  mFileName := FFileName;
  mLine := FCaretLine;
  mFound := nil;
  FRequest.Start(
    procedure
    begin
      mFound := ASession.CodeActions(mFileName, TLspRange.Create(mLine, 0, mLine, Length(mLineText)),
        cActionsTimeoutMs);
    end,
    procedure(AOk: Boolean; const AError: string)
    begin
      ActionFetched(AOk, mFileName, mLineText, mLine, mFound);
    end);
end;

procedure TAtlasIdeGutterColumnState.ActionFetched(AOk: Boolean; const AFileName, ALineText: string; ALine: Integer;
  const AFound: TArray<TLspCodeAction>);
var
  mAction: TLspCodeAction;
  mHad: Boolean;
begin
  if not AOk then
  begin
    FRetryAt := TThread.GetTickCount64 + cRetryMs;
    // Ohne Antwort noch einmal fragen, sonst bliebe die Glühbirne aus, bis die Einfügemarke wandert.
    FAction.Asked := False;
  end;
  // Inzwischen eine andere Zeile gefragt: Diese Antwort gilt nicht mehr.
  if not SameText(FAction.FileName, AFileName) or (FAction.Line <> ALine) or (FAction.Text <> ALineText) then
  begin
    Exit;
  end;
  mHad := FAction.Found;
  FAction.Found := False;
  for mAction in AFound do
  begin
    FAction.Found := FAction.Found or (mAction.Disabled = '');
  end;
  if mHad or FAction.Found then
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
  if FOptions.CodeActions and FAction.Found and (ALine = FAction.Line) and SameText(AFileName, FAction.FileName) then
  begin
    Result.Action := not AHasText or TAtlasRecursionMarks.LineMatches(ALineText, FAction.Text);
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
      AProblem.EndLine, AProblem.EndCharacter), cFixesTimeoutMs);
  except
    on E: ELspClientError do
    begin
      Result := nil;
      AError := E.Message;
    end;
  end;
end;

end.
