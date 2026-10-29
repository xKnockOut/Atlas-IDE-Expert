unit Atlas.IDE.Query.Service;

// Fenster „Atlas-Abfrage“ (#1351) in der IDE:
// - ShowWindow zeigt das Fenster (Ansicht › Atlas › Abfrage, Befehlspalette
//   Atlas.Query) und holt den Katalog (atlas/queryCatalog: Mengen, Felder,
//   Prädikate, gespeicherte Abfragen des aktiven Projekts) für die
//   Vervollständigung und die Auswahl.
// - „Ausführen“ schickt atlas/query für das aktive Projekt im Hintergrund an
//   den laufenden Server (ARequest, abbrechbar). „Abbrechen“ meldet den Abbruch
//   über $/cancelRequest; eine Antwort, die nach einer neueren Anfrage oder nach
//   dem Abbruch kommt, fällt weg. Die Laufzeit des Servers steht in der
//   Statuszeile.
// - Symbolnamen für die Vervollständigung: hinter inherits, implements, calls
//   und has attribute aus der Symbolsuche des Servers (ASymbols, kurzes
//   Zeitlimit), hinter uses die Units des aktiven Projekts.
// - Doppelklick springt zur Deklaration.
// - „Als Regel speichern …“ fragt Name, Beschreibung und Meldung und schreibt
//   den Eintrag nach queries in atlas.json des aktiven Projekts (failIfAny,
//   severity warning; ein Eintrag gleichen Namens wird ersetzt). Der Server
//   liest die Datei neu; danach meldet die Regel query:<name> Befunde.
// - query.enabled aus (oder die Absturzsicherung „Code-Abfragen“): Enabled =
//   False, das Fenster schließt, Menü und Palette blenden den Befehl aus.
// Den Server erreicht der Dienst über ARequest (Install), damit er die
// Zusammensetzung des Plugins nicht kennen muss. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.UI.Query.Frame;

type
  /// <summary>Anfrage AMethod (Parameter als JSON-Objekt) im Hintergrund an den laufenden Server, abbrechbar über
  /// ACancelled (aus dem Hintergrund gefragt); ADone im Hauptthread mit der Antwort als JSON-Text ('' bei Fehler,
  /// Abbruch oder Zeitlimit). False = nicht gestartet (kein Server).</summary>
  TAtlasCodeQueryRequest = reference to function(const AMethod, AParamsJson: string; ATimeoutMs: Cardinal;
    const ACancelled: TFunc<Boolean>; const ADone: TProc<string>): Boolean;

  TAtlasIdeCodeQuery = class
  private class var
    FState: TObject;
    /// <summary>Nummer der laufenden Anfrage; jede neue Anfrage, ein Abbruch und das Entladen zählen weiter. Der
    /// Hintergrund fragt nur diese Zahl ab (nicht FState, das freigegeben sein kann).</summary>
    FCurrent: Integer;
  public
    /// <summary>ARequest: Weg zum Server; ASymbols: Namen aus der Symbolsuche (nil = keine).</summary>
    class procedure Install(const ARequest: TAtlasCodeQueryRequest; const ASymbols: TAtlasCodeQuerySymbols); static;
    class procedure Uninstall; static;
    /// <summary>Fenster zeigen; nichts, solange query.enabled aus ist.</summary>
    class procedure ShowWindow; static;
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    /// <summary>query.enabled an und die Sicherung nicht ausgelöst.</summary>
    class function Enabled: Boolean; static;
  end;

implementation

uses
  System.Classes,
  System.StrUtils,
  System.JSON,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Query.Model,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Settings.Project,
  Atlas.IDE.Query.Window;

const
  /// <summary>Der Server bricht nach vier Fünfteln von requestTimeoutMs selbst ab; das hier ist nur die Grenze für
  /// eine hängende Verbindung.</summary>
  cTimeoutMs = 120000;
  cCatalogTimeoutMs = 10000;
  /// <summary>So viele Zeilen zeigt das Fenster höchstens; die Statuszeile nennt dann „n von m“.</summary>
  cLimit = 5000;
  cSeverity = 'warning';

type
  TCodeQueryState = class
  private
    FRequest: TAtlasCodeQueryRequest;
    FSymbols: TAtlasCodeQuerySymbols;
    /// <summary>Nummer der letzten Katalog-Anfrage; ältere Antworten fallen weg.</summary>
    FCatalogRequest: Integer;
    procedure Wire(AFrame: TAtlasCodeQueryFrame);
    function ProjectUri(out AUri: string): Boolean;
    function Symbols(const APredicate, APrefix: string): TArray<string>;
  public
    constructor Create(const ARequest: TAtlasCodeQueryRequest; const ASymbols: TAtlasCodeQuerySymbols);
    destructor Destroy; override;
    procedure LoadCatalog;
    procedure Run(const AQuery: string);
    procedure Cancel;
    procedure SaveRule(const AQuery: string);
  end;

function Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.QueryEnabled and not TAtlasGuard.Disabled(TAtlasFeature.Query);
end;

/// <summary>Abbruchfrage für die Anfrage ARequest; in eigener Routine, damit der Rahmen nichts anderes festhält.
/// </summary>
function CancelledFor(ARequest: Integer): TFunc<Boolean>;
begin
  Result :=
    function: Boolean
    begin
      Result := TAtlasIdeCodeQuery.FCurrent <> ARequest;
    end;
end;

/// <summary>Units des aktiven Projekts, deren Name mit APrefix beginnt (für „uses“).</summary>
function ProjectUnits(const APrefix: string): TArray<string>;
var
  mModules: IOTAModuleServices;
  mProject: IOTAProject;
  mInfo: IOTAModuleInfo;
  mIndex: Integer;
  mName: string;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
    Exit;
  mProject := mModules.GetActiveProject;
  if mProject = nil then
    Exit;
  for mIndex := 0 to mProject.GetModuleCount - 1 do
  begin
    mInfo := mProject.GetModule(mIndex);
    if (mInfo = nil) or not SameText(ExtractFileExt(mInfo.FileName), '.pas') then
      Continue;
    mName := ChangeFileExt(ExtractFileName(mInfo.FileName), '');
    if StartsText(APrefix, mName) then
      Result := Result + [mName];
  end;
end;

{ TCodeQueryState }

constructor TCodeQueryState.Create(const ARequest: TAtlasCodeQueryRequest; const ASymbols: TAtlasCodeQuerySymbols);
begin
  inherited Create;
  FRequest := ARequest;
  FSymbols := ASymbols;
  TAtlasIdeCodeQueryWindow.OnFrame :=
    procedure(AFrame: TAtlasCodeQueryFrame)
    begin
      Wire(AFrame);
    end;
  // Früh anmelden, damit die IDE das Fenster im Desktop speichert und wiederherstellt (#879).
  TAtlasIdeCodeQueryWindow.Prepare;
  // Das Fenster gab es schon (Paket neu geladen): neu verdrahten.
  if TAtlasIdeCodeQueryWindow.ExistingFrame <> nil then
    Wire(TAtlasIdeCodeQueryWindow.ExistingFrame);
end;

destructor TCodeQueryState.Destroy;
var
  mFrame: TAtlasCodeQueryFrame;
begin
  // Laufende Anfragen brechen ab; Antworten, die noch unterwegs sind, fallen weg.
  Inc(TAtlasIdeCodeQuery.FCurrent);
  Inc(FCatalogRequest);
  TAtlasIdeCodeQueryWindow.OnFrame := nil;
  mFrame := TAtlasIdeCodeQueryWindow.ExistingFrame;
  if mFrame <> nil then
  begin
    mFrame.OnRun := nil;
    mFrame.OnCancel := nil;
    mFrame.OnSaveRule := nil;
    mFrame.OnCopied := nil;
    mFrame.OnOpenLocation := nil;
    mFrame.OnSymbols := nil;
  end;
  inherited Destroy;
end;

procedure TCodeQueryState.Wire(AFrame: TAtlasCodeQueryFrame);
begin
  AFrame.OnRun :=
    procedure(AQuery: string)
    begin
      TAtlasGuard.Run(TAtlasFeature.Query,
        procedure
        begin
          Run(AQuery);
        end);
    end;
  AFrame.OnCancel :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Query,
        procedure
        begin
          Cancel;
        end);
    end;
  AFrame.OnSaveRule :=
    procedure(AQuery: string)
    begin
      TAtlasGuard.Run(TAtlasFeature.Query,
        procedure
        begin
          SaveRule(AQuery);
        end);
    end;
  AFrame.OnOpenLocation :=
    procedure(AFileName: string; ALine, ACharacter: Integer)
    begin
      TAtlasIdeNavigation.GoToLocation(AFileName, ALine - 1, ACharacter - 1);
    end;
  AFrame.OnSymbols :=
    function(const APredicate, APrefix: string): TArray<string>
    begin
      Result := Symbols(APredicate, APrefix);
    end;
  // Vom Desktop wiederhergestellt: Katalog holen, sobald der Aufbau durch ist (dann ist meist auch das Projekt da).
  TAtlasMainThread.Queue(TAtlasFeature.Query,
    procedure
    begin
      if (TAtlasIdeCodeQuery.FState = Self) and Active and TAtlasIdeCodeQueryWindow.Visible then
        LoadCatalog;
    end);
end;

function TCodeQueryState.ProjectUri(out AUri: string): Boolean;
var
  mProject: IOTAProject;
begin
  AUri := '';
  mProject := GetActiveProject;
  Result := (mProject <> nil) and (mProject.FileName <> '');
  if Result then
    AUri := TLspSession.PathToUri(mProject.FileName);
end;

function TCodeQueryState.Symbols(const APredicate, APrefix: string): TArray<string>;
begin
  Result := nil;
  if APredicate = 'uses' then
    Result := ProjectUnits(APrefix)
  else if Assigned(FSymbols) then
    Result := FSymbols(APredicate, APrefix);
end;

procedure TCodeQueryState.LoadCatalog;
var
  mUri: string;
  mRequest: Integer;
begin
  if not ProjectUri(mUri) then
    mUri := '';
  Inc(FCatalogRequest);
  mRequest := FCatalogRequest;
  FRequest(TAtlasQueryRequest.CatalogMethod, TAtlasQueryRequest.CatalogParams(mUri), cCatalogTimeoutMs, nil,
    procedure(AAnswer: string)
    var
      mCatalog: TAtlasQueryCatalog;
      mFrame: TAtlasCodeQueryFrame;
    begin
      if (TAtlasIdeCodeQuery.FState <> Self) or (mRequest <> FCatalogRequest) then
        Exit;
      mFrame := TAtlasIdeCodeQueryWindow.ExistingFrame;
      if (mFrame <> nil) and TAtlasQueryCatalog.Parse(AAnswer, mCatalog) and mCatalog.Enabled then
        mFrame.SetCatalog(mCatalog);
    end);
end;

procedure TCodeQueryState.Run(const AQuery: string);
var
  mFrame: TAtlasCodeQueryFrame;
  mUri: string;
  mRequest: Integer;
begin
  mFrame := TAtlasIdeCodeQueryWindow.ExistingFrame;
  if mFrame = nil then
    Exit;
  if not ProjectUri(mUri) then
  begin
    mFrame.SetMessage(TAtlasStrings.Text(TAtlasTextId.QueryNoProject), True);
    Exit;
  end;
  Inc(TAtlasIdeCodeQuery.FCurrent);
  mRequest := TAtlasIdeCodeQuery.FCurrent;
  mFrame.SetRunning(True);
  if not FRequest(TAtlasQueryRequest.Method, TAtlasQueryRequest.Params(mUri, AQuery, cLimit), cTimeoutMs,
    CancelledFor(mRequest),
    procedure(AAnswer: string)
    var
      mAnswer: TAtlasQueryAnswer;
      mCurrent: TAtlasCodeQueryFrame;
    begin
      if (TAtlasIdeCodeQuery.FState <> Self) or (mRequest <> TAtlasIdeCodeQuery.FCurrent) then
        Exit;
      mCurrent := TAtlasIdeCodeQueryWindow.ExistingFrame;
      if mCurrent = nil then
        Exit;
      if not TAtlasQueryAnswer.Parse(AAnswer, mAnswer) then
        mCurrent.SetMessage(TAtlasStrings.Text(TAtlasTextId.QueryFailed), True)
      else if not mAnswer.Enabled then
        mCurrent.SetMessage(TAtlasStrings.Text(TAtlasTextId.QueryDisabled), False)
      else
        mCurrent.SetAnswer(mAnswer);
    end) then
    mFrame.SetMessage(TAtlasStrings.Text(TAtlasTextId.QueryNoServer), True);
end;

procedure TCodeQueryState.Cancel;
var
  mFrame: TAtlasCodeQueryFrame;
begin
  // Die Abbruchfrage im Hintergrund sieht die neue Nummer und meldet $/cancelRequest; die Antwort fällt weg.
  Inc(TAtlasIdeCodeQuery.FCurrent);
  mFrame := TAtlasIdeCodeQueryWindow.ExistingFrame;
  if mFrame <> nil then
    mFrame.SetMessage(TAtlasStrings.Text(TAtlasTextId.QueryCancelled), True);
end;

procedure TCodeQueryState.SaveRule(const AQuery: string);
var
  mFrame: TAtlasCodeQueryFrame;
  mValues: array[0..2] of string;
  mProject: TJSONObject;
  mExisting: TJSONValue;
  mExistingJson: string;
  mSaved: TAtlasSavedQuery;
begin
  mFrame := TAtlasIdeCodeQueryWindow.ExistingFrame;
  if mFrame = nil then
    Exit;
  if TAtlasProjectSettings.SettingsFile = '' then
  begin
    mFrame.SetMessage(TAtlasStrings.Text(TAtlasTextId.QueryRuleNoProject), True);
    Exit;
  end;
  mValues[0] := '';
  mValues[1] := '';
  mValues[2] := '';
  if not InputQuery(TAtlasStrings.Text(TAtlasTextId.QueryRuleTitle),
    [TAtlasStrings.Text(TAtlasTextId.QueryRuleName), TAtlasStrings.Text(TAtlasTextId.QueryRuleDescription),
    TAtlasStrings.Text(TAtlasTextId.QueryRuleMessage)], mValues) then
    Exit;
  mSaved := Default(TAtlasSavedQuery);
  mSaved.Name := Trim(mValues[0]);
  mSaved.Query := AQuery;
  mSaved.Description := Trim(mValues[1]);
  mSaved.FailIfAny := True;
  if not TAtlasSavedQueries.ValidName(mSaved.Name) then
  begin
    mFrame.SetMessage(TAtlasStrings.Text(TAtlasTextId.QueryRuleBadName), True);
    Exit;
  end;
  mExistingJson := '';
  mProject := TAtlasProjectSettings.ReadProject;
  try
    if mProject <> nil then
    begin
      mExisting := mProject.GetValue('queries');
      if mExisting is TJSONArray then
        mExistingJson := mExisting.ToJSON([]);
    end;
  finally
    mProject.Free;
  end;
  if not TAtlasProjectSettings.WriteValue('queries',
    TAtlasSavedQueries.WithQuery(mExistingJson, mSaved, cSeverity, Trim(mValues[2]))) then
  begin
    mFrame.SetMessage(TAtlasStrings.Text(TAtlasTextId.QueryRuleNoProject), True);
    Exit;
  end;
  mFrame.SetMessage(TAtlasStrings.Fmt(TAtlasTextId.QueryRuleSaved,
    [ExtractFileName(TAtlasProjectSettings.SettingsFile), mSaved.Name]), True);
  // Die neue Abfrage gleich in der Auswahl zeigen (der Server liest atlas.json über seinen Dateibeobachter).
  LoadCatalog;
end;

{ TAtlasIdeCodeQuery }

class procedure TAtlasIdeCodeQuery.Install(const ARequest: TAtlasCodeQueryRequest;
  const ASymbols: TAtlasCodeQuerySymbols);
begin
  FreeAndNil(FState);
  FState := TCodeQueryState.Create(ARequest, ASymbols);
end;

class procedure TAtlasIdeCodeQuery.Uninstall;
begin
  FreeAndNil(FState);
  TAtlasIdeCodeQueryWindow.Release;
end;

class function TAtlasIdeCodeQuery.Enabled: Boolean;
begin
  Result := Active;
end;

class procedure TAtlasIdeCodeQuery.ShowWindow;
var
  mFrame: TAtlasCodeQueryFrame;
begin
  if (FState = nil) or not Active then
    Exit;
  mFrame := TAtlasIdeCodeQueryWindow.Show;
  if mFrame = nil then
    Exit;
  // Gespeicherte Abfragen können sich geändert haben (atlas.json, anderes Projekt): bei jedem Zeigen neu holen.
  TCodeQueryState(FState).LoadCatalog;
  if mFrame.Input.CanFocus and mFrame.Showing then
    mFrame.Input.SetFocus;
end;

class procedure TAtlasIdeCodeQuery.ApplySettings;
begin
  if FState = nil then
    Exit;
  if not Active then
  begin
    // Laufende Anfrage abbrechen und das Fenster schließen.
    Inc(FCurrent);
    TAtlasIdeCodeQueryWindow.Hide;
  end;
end;

class procedure TAtlasIdeCodeQuery.ThemeChanged;
begin
  TAtlasIdeCodeQueryWindow.ApplyTheme;
end;

end.
