unit Atlas.IDE.Assistants.Adapters.Link;

// Assistenten-Kopplung (#2377, assistants.link): RAD Studio als verbundene IDE für Kommandozeilen-Assistenten.
// Adapter, weil die Kopplung den Vertrag Atlas.Core.Assistants.Contract.Link für die IDE erfüllt; nur die
// Composition bindet sie ein.
// Beim Start öffnet die Kopplung den WebSocket-Server (Atlas.IDE.Assistants.LinkServer) mit Zufallsport und Token je
// IDE-Sitzung und kündigt ihn mit einer Lock-Datei im Konfigurationsordner des Clients an; Destroy löscht sie
// wieder. Ein Zeitgeber im Hauptthread holt die Ereignisse des Servers ab: Je Verbindung beantwortet eine
// TAtlasLinkSession die Nachrichten, die IDE erreicht sie über einen eigenen Adapter je Verbindung. Daneben:
// - Auswahl im Editor alle cSelectionMs lesen; ruht sie, geht selection_changed an alle Verbindungen
//   (assistants.link.shareSelection).
// - Vorschläge aus openDiff als Vergleichsfenster (Atlas.UI.Assistants.LinkDiffView). Annehmen wendet die Änderung
//   als einen Rückgängig-Schritt an und speichert; erst dann geht die Antwort an den Assistenten. Hat sich die Datei
//   seit dem Zeigen geändert, zeigt das Fenster den neuen Stand und wartet erneut. Trennt eine Verbindung, werden
//   ihre Vorschläge abgelehnt und die Fenster geschlossen.
// - Feld „Assistent verbunden“ im Statusfeld; Klick öffnet ein Menü mit „Trennen“.
// - Mention: Datei und Zeilen der Auswahl als at_mentioned an alle Verbindungen (Befehl „Auswahl an den
//   Assistenten“).
// Nach Destroy erreicht nichts mehr das Modul: Server und Zeitgeber sind fort, Gegenstellen und Adapter abgehängt,
// Fenster freigegeben (ADR 0017 Regel 3). Nur im Hauptthread.

interface

uses
  System.Types,
  System.SysUtils,
  System.Generics.Collections,
  Vcl.ExtCtrls,
  Vcl.Menus,
  Atlas.Core.Assistants.Activity,
  Atlas.Core.Assistants.Contract.Link,
  Atlas.Core.Assistants.LinkProtocol,
  Atlas.Core.Assistants.LinkState,
  Atlas.IDE.Assistants.LinkServer,
  Atlas.UI.Assistants.LinkDiffView;

type
  /// <summary>Offene Vorschläge aus openDiff mit ihren Vergleichsfenstern.</summary>
  TAtlasIdeLinkProposals = class
  private
    FActivity: TAtlasAssistantsActivity;
    FClients: TFunc<string>;
    FDiffs: TAtlasLinkDiffs;
    FViews: TDictionary<Integer, TAtlasLinkDiffView>;
    FRetired: TObjectList<TAtlasLinkDiffView>;
    procedure ViewDecided(AId: Integer; ADecision: TAtlasLinkDecision);
    function Apply(const ADiff: TAtlasLinkDiff; out AChanged: Boolean): string;
    procedure Reject(AId: Integer);
    procedure Retire(AId: Integer);
    function Close(const AIds: TArray<Integer>): Integer;
  public
    /// <summary>AActivity: Anzeige „KI-Assistent aktiv“; AClients: Namen der verbundenen Assistenten.</summary>
    constructor Create(AActivity: TAtlasAssistantsActivity; const AClients: TFunc<string>);
    /// <summary>Lehnt offene Vorschläge ab (die Antwort geht hinaus, solange die Gegenstelle besteht) und gibt die
    /// Fenster frei.</summary>
    destructor Destroy; override;
    /// <summary>Vorschlag der Verbindung AOwner zeigen; ADone nach der Entscheidung.</summary>
    procedure Show(AOwner: Integer; const ARequest: TAtlasLinkDiffRequest; const ADone: TAtlasLinkDiffDone);
    /// <summary>Vorschläge mit dem Namen ATabName schließen (abgelehnt); Ergebnis ihre Zahl.</summary>
    function CloseNamed(const ATabName: string): Integer;
    /// <summary>Vorschläge der Verbindung AOwner schließen (abgelehnt); Ergebnis ihre Zahl.</summary>
    function CloseOf(AOwner: Integer): Integer;
    /// <summary>Fenster freigeben, die in ihrem eigenen Ereignis entschieden haben (im nächsten Takt).</summary>
    procedure Collect;
  end;

  TAtlasIdeLink = class
  public const
    cFieldId = 'atlas.assistants.link';
    /// <summary>Takt für die Ereignisse des Servers.</summary>
    cTickMs = 50;
    /// <summary>So oft wird die Auswahl gelesen.</summary>
    cSelectionMs = 250;
    /// <summary>So oft werden die Arbeitsordner in der Lock-Datei nachgeführt.</summary>
    cFoldersMs = 2000;
  private type
    /// <summary>Ausgang einer Verbindung; nach Detach tut Send nichts.</summary>
    TPeer = class(TInterfacedObject, IAtlasLinkPeer)
    private
      FServer: TAtlasLinkServer;
      FConnection: Integer;
    public
      constructor Create(AServer: TAtlasLinkServer; AConnection: Integer);
      procedure Send(const AJson: string);
      procedure Detach;
    end;

    /// <summary>Die IDE für eine Verbindung; nach Detach liefert sie nichts und tut nichts.</summary>
    TIde = class(TInterfacedObject, IAtlasLinkIde)
    private
      FOwner: TAtlasIdeLink;
      FConnection: Integer;
    public
      constructor Create(AOwner: TAtlasIdeLink; AConnection: Integer);
      procedure Detach;
      function WorkspaceFolders: TArray<string>;
      function OpenTabs: TArray<TAtlasLinkTab>;
      function CurrentSelection: TAtlasLinkSelection;
      function LatestSelection: TAtlasLinkSelection;
      function OpenFile(const ARequest: TAtlasLinkOpenRequest): TAtlasLinkOpenResult;
      function Document(const AFileName: string): TAtlasLinkDocument;
      function SaveDocument(const AFileName: string): Boolean;
      function Diagnostics(const AFileName: string): TArray<TAtlasLinkDiagnostic>;
      procedure OpenDiff(const ARequest: TAtlasLinkDiffRequest; const ADone: TAtlasLinkDiffDone);
      function CloseTab(const ATabName: string): Boolean;
      function CloseAllDiffs: Integer;
      function Paused: Boolean;
    end;

    /// <summary>Eine Verbindung mit Gegenstelle, IDE-Adapter und Sitzung.</summary>
    TConnection = class
    private
      FId: Integer;
      FPeer: TPeer;
      FPeerRef: IAtlasLinkPeer;
      FIde: TIde;
      FIdeRef: IAtlasLinkIde;
      FSession: TAtlasLinkSession;
    public
      constructor Create(AOwner: TAtlasIdeLink; AServer: TAtlasLinkServer; AId: Integer);
      destructor Destroy; override;
      property Id: Integer read FId;
      property Peer: IAtlasLinkPeer read FPeerRef;
      property Session: TAtlasLinkSession read FSession;
    end;
  private
    FActivity: TAtlasAssistantsActivity;
    FServer: TAtlasLinkServer;
    FTimer: TTimer;
    FMenu: TPopupMenu;
    FLockFile: string;
    FToken: string;
    FFolders: string;
    FConnections: TObjectList<TConnection>;
    FSelections: TAtlasLinkSelections;
    FSelectionKey: string;
    FSelectionText: string;
    FProposals: TAtlasIdeLinkProposals;
    FLastSelectionMs: UInt64;
    FLastFoldersMs: UInt64;
    FShown: string;
    FShareSelection: Boolean;
    FDiffPreview: Boolean;
    procedure Tick(Sender: TObject);
    procedure TakeEvents;
    procedure Opened(AConnection: Integer);
    procedure Received(AConnection: Integer; const AText: string);
    procedure Disconnected(AConnection: Integer);
    function FindConnection(AConnection: Integer): TConnection;
    procedure Broadcast(const AJson: string);
    procedure FollowSelection(ANowMs: UInt64);
    procedure WriteLock(AForce: Boolean);
    procedure RefreshStatus;
    procedure StatusClicked(APoint: TPoint);
    procedure DisconnectClicked(Sender: TObject);
    function ClientNames: string;
  public
    /// <summary>AActivity gehört der Composition und lebt länger als die Kopplung (Pause, Anzeige „KI-Assistent
    /// aktiv“).</summary>
    constructor Create(AActivity: TAtlasAssistantsActivity);
    destructor Destroy; override;
    /// <summary>Einstellungen assistants.link.* übernehmen (gilt sofort bzw. ab dem nächsten tools/list).</summary>
    procedure ApplySettings;
    /// <summary>Datei und Zeilen der Auswahl an alle Verbindungen (at_mentioned).</summary>
    procedure Mention;
    /// <summary>Mindestens ein Assistent ist verbunden.</summary>
    function IsConnected: Boolean;
    /// <summary>Alle Verbindungen trennen.</summary>
    procedure DisconnectAll;
    /// <summary>Befehl der Kopplung, Fehler gemeldet statt in die IDE geworfen.</summary>
    class function Guarded(const ARun: TProc): TProc; static;
  end;

implementation

uses
  Winapi.Windows,
  System.StrUtils,
  Atlas.Core.Status.Contract,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.Plugin.Files.DataFile,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Core.Assistants.EditPlan,
  Atlas.Core.Assistants.LinkLock,
  Atlas.Text.Product.Version,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Assistants.LinkEditor,
  Atlas.UI.Assistants.Strings;

const
  /// <summary>Art der Datei im Protokoll, wenn sie nicht geschrieben werden konnte.</summary>
  cLockKind = 'Lock-Datei der Assistenten-Kopplung'; // german-ok: Protokoll, wie die anderen Ablagen

/// <summary>Die zufälligen Bytes einer Version-4-GUID: D1, D2 und D4 ohne das Byte der Variante (D3 trägt die
/// Version).</summary>
function RandomPart(const AGuid: TGUID): TBytes;
var
  mOffset: Integer;
begin
  Result := nil;
  SetLength(Result, SizeOf(AGuid.D1) + SizeOf(AGuid.D2) + High(AGuid.D4));
  Move(AGuid.D1, Result[0], SizeOf(AGuid.D1));
  mOffset := SizeOf(AGuid.D1);
  Move(AGuid.D2, Result[mOffset], SizeOf(AGuid.D2));
  Inc(mOffset, SizeOf(AGuid.D2));
  Move(AGuid.D4[1], Result[mOffset], High(AGuid.D4));
end;

/// <summary>Zufallsbytes aus dem Betriebssystem (Version-4-GUIDs, erzeugt über den kryptografischen Zufall von
/// Windows).</summary>
function RandomBytes(ACount: Integer): TBytes;
var
  mAll: TBytes;
begin
  mAll := nil;
  while Length(mAll) < ACount do
  begin
    mAll := mAll + RandomPart(TGUID.NewGuid);
  end;
  Result := Copy(mAll, 0, ACount);
end;

function RandomCardinal: Cardinal;
var
  mBytes: TBytes;
begin
  mBytes := RandomBytes(SizeOf(Cardinal));
  Move(mBytes[0], Result, SizeOf(Cardinal));
end;

/// <summary>Version von RAD Studio aus der Compilerversion (36 = 12, 37 = 13).</summary>
function StudioVersion: string;
const
  cCompilerToStudio = 24;
begin
  Result := IntToStr(Trunc(CompilerVersion) - cCompilerToStudio);
end;

/// <summary>Datei, die ein Vorschlag ändert.</summary>
function TargetOf(const ARequest: TAtlasLinkDiffRequest): string;
begin
  Result := ARequest.NewFileName;
  if Result = '' then
  begin
    Result := ARequest.OldFileName;
  end;
end;

/// <summary>„ · Name“, '' ohne Namen.</summary>
function NamePart(const AName: string): string;
begin
  Result := '';
  if AName <> '' then
  begin
    Result := ' · ' + AName;
  end;
end;

function ApplyInEditor(const AEdit: TLspWorkspaceEdit): string;
begin
  Result := TAtlasIdeWorkspaceEdit.Apply(AEdit, TAtlasUnopenedPolicy.WriteToDisk,
    TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.UndoActionLink)).Error;
end;

{ TAtlasIdeLink.TPeer }

constructor TAtlasIdeLink.TPeer.Create(AServer: TAtlasLinkServer; AConnection: Integer);
begin
  inherited Create;
  FServer := AServer;
  FConnection := AConnection;
end;

procedure TAtlasIdeLink.TPeer.Send(const AJson: string);
begin
  if FServer <> nil then
  begin
    FServer.Send(FConnection, AJson);
  end;
end;

procedure TAtlasIdeLink.TPeer.Detach;
begin
  FServer := nil;
end;

{ TAtlasIdeLink.TIde }

constructor TAtlasIdeLink.TIde.Create(AOwner: TAtlasIdeLink; AConnection: Integer);
begin
  inherited Create;
  FOwner := AOwner;
  FConnection := AConnection;
end;

procedure TAtlasIdeLink.TIde.Detach;
begin
  FOwner := nil;
end;

function TAtlasIdeLink.TIde.WorkspaceFolders: TArray<string>;
begin
  Result := nil;
  if FOwner <> nil then
  begin
    Result := TAtlasIdeLinkEditor.Folders;
  end;
end;

function TAtlasIdeLink.TIde.OpenTabs: TArray<TAtlasLinkTab>;
begin
  Result := nil;
  if FOwner <> nil then
  begin
    Result := TAtlasIdeLinkEditor.Tabs;
  end;
end;

function TAtlasIdeLink.TIde.CurrentSelection: TAtlasLinkSelection;
begin
  Result := Default(TAtlasLinkSelection);
  if FOwner <> nil then
  begin
    Result := TAtlasIdeLinkEditor.Selection(FOwner.FSelectionKey, FOwner.FSelectionText);
  end;
end;

function TAtlasIdeLink.TIde.LatestSelection: TAtlasLinkSelection;
begin
  Result := Default(TAtlasLinkSelection);
  if FOwner <> nil then
  begin
    Result := FOwner.FSelections.Latest;
  end;
end;

function TAtlasIdeLink.TIde.OpenFile(const ARequest: TAtlasLinkOpenRequest): TAtlasLinkOpenResult;
begin
  Result := Default(TAtlasLinkOpenResult);
  if FOwner <> nil then
  begin
    Result := TAtlasIdeLinkEditor.OpenFile(ARequest);
  end;
end;

function TAtlasIdeLink.TIde.Document(const AFileName: string): TAtlasLinkDocument;
begin
  Result := Default(TAtlasLinkDocument);
  if FOwner <> nil then
  begin
    Result := TAtlasIdeLinkEditor.Document(AFileName);
  end;
end;

function TAtlasIdeLink.TIde.SaveDocument(const AFileName: string): Boolean;
begin
  Result := (FOwner <> nil) and TAtlasIdeLinkEditor.Save(AFileName);
end;

function TAtlasIdeLink.TIde.Diagnostics(const AFileName: string): TArray<TAtlasLinkDiagnostic>;
begin
  Result := nil;
  if FOwner <> nil then
  begin
    Result := TAtlasIdeLinkEditor.Diagnostics(AFileName);
  end;
end;

procedure TAtlasIdeLink.TIde.OpenDiff(const ARequest: TAtlasLinkDiffRequest; const ADone: TAtlasLinkDiffDone);
begin
  if FOwner = nil then
  begin
    ADone(False, '');
    Exit;
  end;
  FOwner.FProposals.Show(FConnection, ARequest, ADone);
end;

function TAtlasIdeLink.TIde.CloseTab(const ATabName: string): Boolean;
begin
  Result := (FOwner <> nil) and (FOwner.FProposals.CloseNamed(ATabName) > 0);
end;

function TAtlasIdeLink.TIde.CloseAllDiffs: Integer;
begin
  Result := 0;
  if FOwner <> nil then
  begin
    Result := FOwner.FProposals.CloseOf(FConnection);
  end;
end;

function TAtlasIdeLink.TIde.Paused: Boolean;
begin
  Result := (FOwner = nil) or FOwner.FActivity.Paused;
end;

{ TAtlasIdeLink.TConnection }

constructor TAtlasIdeLink.TConnection.Create(AOwner: TAtlasIdeLink; AServer: TAtlasLinkServer; AId: Integer);
begin
  inherited Create;
  FId := AId;
  FPeer := TPeer.Create(AServer, AId);
  FPeerRef := FPeer;
  FIde := TIde.Create(AOwner, AId);
  FIdeRef := FIde;
  FSession := TAtlasLinkSession.Create(FIdeRef, FPeerRef, TAtlasVersion.cVersion);
end;

destructor TAtlasIdeLink.TConnection.Destroy;
begin
  // Antworten auf offene Vorschläge und späte Aufrufe der Sitzung gehen danach ins Leere.
  if FPeer <> nil then
  begin
    FPeer.Detach;
  end;
  if FIde <> nil then
  begin
    FIde.Detach;
  end;
  FSession.Free;
  FPeerRef := nil;
  FIdeRef := nil;
  inherited Destroy;
end;

{ TAtlasIdeLink }

constructor TAtlasIdeLink.Create(AActivity: TAtlasAssistantsActivity);
var
  mItem: TMenuItem;
begin
  inherited Create;
  FActivity := AActivity;
  FConnections := TObjectList<TConnection>.Create(True);
  FSelections := TAtlasLinkSelections.Create;
  FProposals := TAtlasIdeLinkProposals.Create(FActivity,
    function: string
    begin
      Result := ClientNames;
    end);
  FMenu := TPopupMenu.Create(nil);
  mItem := TMenuItem.Create(FMenu);
  mItem.Caption := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LinkDisconnect);
  mItem.OnClick := DisconnectClicked;
  FMenu.Items.Add(mItem);
  ApplySettings;
  FToken := TAtlasLinkLock.TokenOf(RandomBytes(TAtlasLinkLock.cTokenBytes));
  FServer := TAtlasLinkServer.Create(FToken, TAtlasLinkLock.cTokenHeader);
  if not FServer.Open(RandomCardinal) then
  begin
    TAtlasIdeHost.Warning(TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LinkNoPort));
    FreeAndNil(FServer);
  end
  else
  begin
    FLockFile := TAtlasLinkLock.FileName(TAtlasLinkLock.Folder(GetEnvironmentVariable('USERPROFILE'),
      GetEnvironmentVariable(TAtlasLinkLock.cConfigVariable)), FServer.Port);
    WriteLock(True);
  end;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := FServer <> nil;
end;

destructor TAtlasIdeLink.Destroy;
begin
  FreeAndNil(FTimer);
  // Erst die Vorschläge: Ihre Fenster sollen nach dem Abbau nichts mehr auslösen; die Ablehnung geht noch hinaus,
  // solange der Server steht.
  FreeAndNil(FProposals);
  // Sitzungen vor dem Server: Ihre Gegenstellen werden dabei abgehängt.
  if FConnections <> nil then
  begin
    FConnections.Clear;
  end;
  FreeAndNil(FServer);
  if FLockFile <> '' then
  begin
    TAtlasDataFile.RemoveQuietly(FLockFile);
  end;
  TAtlasIdeHost.SetStatusField(cFieldId, '', '', nil);
  FMenu.Free;
  FSelections.Free;
  FConnections.Free;
  inherited Destroy;
end;

procedure TAtlasIdeLink.ApplySettings;
var
  mConnection: TConnection;
begin
  FShareSelection := TAtlasIdeSettings.Current.AssistantsLinkShareSelection;
  FDiffPreview := TAtlasIdeSettings.Current.AssistantsLinkDiffPreview;
  for mConnection in FConnections do
  begin
    mConnection.Session.OffersDiffs := FDiffPreview;
  end;
  FShown := #0;
  RefreshStatus;
end;

procedure TAtlasIdeLink.WriteLock(AForce: Boolean);
var
  mFolders: TArray<string>;
  mJoined: string;
begin
  if FLockFile = '' then
  begin
    Exit;
  end;
  mFolders := TAtlasIdeLinkEditor.Folders;
  mJoined := string.Join(#10, mFolders);
  if not AForce and (mJoined = FFolders) then
  begin
    Exit;
  end;
  FFolders := mJoined;
  try
    TAtlasDataFile.Write(FLockFile, TAtlasLinkLock.Content(GetCurrentProcessId, mFolders,
      TAtlasLinkLock.IdeName(StudioVersion), FToken));
  except
    on E: Exception do
    begin
      TAtlasDataFile.ReportNotWritten(cLockKind, E);
      if AForce then
      begin
        TAtlasIdeHost.Warning(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.LinkLockFailed, [E.Message]));
      end;
    end;
  end;
end;

procedure TAtlasIdeLink.Tick(Sender: TObject);
var
  mNow: UInt64;
begin
  try
    // Fenster, die in ihrem eigenen Ereignis entschieden haben, erst jetzt freigeben.
    FProposals.Collect;
    TakeEvents;
    mNow := GetTickCount64;
    if (FConnections.Count > 0) and (mNow - FLastSelectionMs >= cSelectionMs) then
    begin
      FLastSelectionMs := mNow;
      FollowSelection(mNow);
    end;
    if mNow - FLastFoldersMs >= cFoldersMs then
    begin
      FLastFoldersMs := mNow;
      WriteLock(False);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Server, E);
  end;
end;

procedure TAtlasIdeLink.TakeEvents;
var
  mEvent: TAtlasLinkServerEvent;
begin
  if FServer = nil then
  begin
    Exit;
  end;
  for mEvent in FServer.TakeEvents do
  begin
    case mEvent.Kind of
      TAtlasLinkServerEventKind.Connected:
        Opened(mEvent.Connection);
      TAtlasLinkServerEventKind.Message:
        Received(mEvent.Connection, mEvent.Text);
      TAtlasLinkServerEventKind.Disconnected:
        Disconnected(mEvent.Connection);
    end;
  end;
end;

function TAtlasIdeLink.FindConnection(AConnection: Integer): TConnection;
var
  mConnection: TConnection;
begin
  for mConnection in FConnections do
  begin
    if mConnection.Id = AConnection then
    begin
      Result := mConnection;
      Exit;
    end;
  end;
  Result := nil;
end;

procedure TAtlasIdeLink.Opened(AConnection: Integer);
var
  mConnection: TConnection;
begin
  mConnection := TConnection.Create(Self, FServer, AConnection);
  mConnection.Session.OffersDiffs := FDiffPreview;
  FConnections.Add(mConnection);
  // Die neue Verbindung soll die jetzige Auswahl erfahren, auch wenn sie sich nicht ändert.
  FSelections.Forget;
  RefreshStatus;
end;

procedure TAtlasIdeLink.Received(AConnection: Integer; const AText: string);
var
  mConnection: TConnection;
  mWasInitialized: Boolean;
begin
  mConnection := FindConnection(AConnection);
  if mConnection = nil then
  begin
    Exit;
  end;
  mWasInitialized := mConnection.Session.Initialized;
  mConnection.Session.Handle(AText);
  if not mWasInitialized and mConnection.Session.Initialized then
  begin
    TAtlasIdeHost.Message(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.LinkConnected,
      [NamePart(mConnection.Session.ClientName)]));
    FSelections.Forget;
    RefreshStatus;
  end;
end;

procedure TAtlasIdeLink.Disconnected(AConnection: Integer);
var
  mConnection: TConnection;
  mName: string;
  mWasInitialized: Boolean;
begin
  mConnection := FindConnection(AConnection);
  if mConnection = nil then
  begin
    Exit;
  end;
  mName := mConnection.Session.ClientName;
  mWasInitialized := mConnection.Session.Initialized;
  // Vorschläge dieser Verbindung verwerfen; die Antwort geht ins Leere.
  FProposals.CloseOf(AConnection);
  FConnections.Remove(mConnection);
  if mWasInitialized then
  begin
    TAtlasIdeHost.Message(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.LinkDisconnected, [NamePart(mName)]));
  end;
  RefreshStatus;
end;

function TAtlasIdeLink.IsConnected: Boolean;
var
  mConnection: TConnection;
begin
  for mConnection in FConnections do
  begin
    if mConnection.Session.Initialized then
    begin
      Result := True;
      Exit;
    end;
  end;
  Result := False;
end;

procedure TAtlasIdeLink.Broadcast(const AJson: string);
var
  mConnection: TConnection;
begin
  for mConnection in FConnections do
  begin
    if mConnection.Session.Initialized then
    begin
      mConnection.Peer.Send(AJson);
    end;
  end;
end;

procedure TAtlasIdeLink.FollowSelection(ANowMs: UInt64);
var
  mSelection: TAtlasLinkSelection;
begin
  mSelection := TAtlasIdeLinkEditor.Selection(FSelectionKey, FSelectionText);
  // Die letzte Auswahl führt die Kopplung immer nach (getLatestSelection); gemeldet wird nur mit shareSelection.
  if FSelections.Due(mSelection, ANowMs) and FShareSelection then
  begin
    Broadcast(TAtlasLinkMessages.SelectionChanged(mSelection));
  end;
end;

class function TAtlasIdeLink.Guarded(const ARun: TProc): TProc;
begin
  Result := TAtlasGuard.Wrap(TAtlasFeature.Server, ARun);
end;

procedure TAtlasIdeLink.Mention;
var
  mFileName: string;
  mLineStart: Integer;
  mLineEnd: Integer;
begin
  if not IsConnected or not TAtlasIdeLinkEditor.Mention(mFileName, mLineStart, mLineEnd) then
  begin
    TAtlasIdeHost.Message(TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LinkMentionNone));
    Exit;
  end;
  Broadcast(TAtlasLinkMessages.AtMentioned(mFileName, mLineStart, mLineEnd));
  TAtlasIdeHost.Message(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.LinkMentionSent,
    [ExtractFileName(mFileName), mLineStart + 1, mLineEnd + 1]));
end;

function TAtlasIdeLink.ClientNames: string;
var
  mConnection: TConnection;
  mNames: TArray<string>;
begin
  mNames := nil;
  for mConnection in FConnections do
  begin
    if mConnection.Session.Initialized and (mConnection.Session.ClientName <> '') and
      (IndexText(mConnection.Session.ClientName, mNames) < 0) then
    begin
      mNames := mNames + [mConnection.Session.ClientName];
    end;
  end;
  Result := string.Join(', ', mNames);
end;

procedure TAtlasIdeLink.RefreshStatus;
var
  mExtra: TAtlasStatusExtra;
begin
  mExtra := Default(TAtlasStatusExtra);
  mExtra.Id := cFieldId;
  if IsConnected then
  begin
    mExtra.Text := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.LinkStatus, [NamePart(ClientNames)]);
    if FShareSelection then
    begin
      mExtra.Text := mExtra.Text + TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LinkStatusSharing);
    end;
  end;
  if mExtra.Text = FShown then
  begin
    Exit;
  end;
  FShown := mExtra.Text;
  if mExtra.Text <> '' then
  begin
    mExtra.Hint := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LinkStatusHint);
    mExtra.State := TAtlasStatusState.Green;
    mExtra.OnClick := StatusClicked;
  end;
  TAtlasIdeHost.SetStatusItem(mExtra);
end;

procedure TAtlasIdeLink.StatusClicked(APoint: TPoint);
begin
  FMenu.Popup(APoint.X, APoint.Y);
end;

procedure TAtlasIdeLink.DisconnectClicked(Sender: TObject);
begin
  DisconnectAll;
end;

procedure TAtlasIdeLink.DisconnectAll;
var
  mConnection: TConnection;
begin
  if FServer = nil then
  begin
    Exit;
  end;
  // Der Server meldet danach Disconnected; erst dann werden Sitzung und Vorschläge abgebaut.
  for mConnection in FConnections do
  begin
    FServer.Drop(mConnection.Id);
  end;
end;

{ TAtlasIdeLinkProposals }

constructor TAtlasIdeLinkProposals.Create(AActivity: TAtlasAssistantsActivity; const AClients: TFunc<string>);
begin
  inherited Create;
  FActivity := AActivity;
  FClients := AClients;
  FDiffs := TAtlasLinkDiffs.Create;
  FViews := TDictionary<Integer, TAtlasLinkDiffView>.Create;
  FRetired := TObjectList<TAtlasLinkDiffView>.Create(True);
end;

destructor TAtlasIdeLinkProposals.Destroy;
var
  mView: TAtlasLinkDiffView;
begin
  if FViews <> nil then
  begin
    for mView in FViews.Values do
    begin
      mView.OnDecide := nil;
      mView.Free;
    end;
  end;
  if FDiffs <> nil then
  begin
    FDiffs.RejectAll;
  end;
  FRetired.Free;
  FViews.Free;
  FDiffs.Free;
  inherited Destroy;
end;

procedure TAtlasIdeLinkProposals.Collect;
begin
  FRetired.Clear;
end;

function TAtlasIdeLinkProposals.CloseNamed(const ATabName: string): Integer;
begin
  Result := Close(FDiffs.IdsNamed(ATabName));
end;

function TAtlasIdeLinkProposals.CloseOf(AOwner: Integer): Integer;
begin
  Result := Close(FDiffs.IdsOf(AOwner));
end;

procedure TAtlasIdeLinkProposals.Show(AOwner: Integer; const ARequest: TAtlasLinkDiffRequest;
  const ADone: TAtlasLinkDiffDone);
var
  mTarget: string;
  mOld: string;
  mId: Integer;
  mView: TAtlasLinkDiffView;
  mRequest: TAtlasLinkDiffRequest;
begin
  mTarget := TargetOf(ARequest);
  mOld := TAtlasIdeLinkEditor.CurrentText(mTarget);
  mRequest := ARequest;
  mRequest.NewText := TAtlasLinkText.MatchBreaks(mOld, ARequest.NewText);
  mId := FDiffs.Add(AOwner, mRequest, mOld, ADone);
  mView := TAtlasLinkDiffView.CreateView(nil, mId,
    TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.LinkDiffTitle, [ExtractFileName(mTarget)]),
    TAtlasLinkDiffView.DiffLines(ExtractFileName(mTarget), mOld, mRequest.NewText));
  mView.OnDecide := ViewDecided;
  FViews.Add(mId, mView);
  mView.Show;
end;

procedure TAtlasIdeLinkProposals.ViewDecided(AId: Integer; ADecision: TAtlasLinkDecision);
var
  mDiff: TAtlasLinkDiff;
  mTarget: string;
  mError: string;
  mChanged: Boolean;
  mView: TAtlasLinkDiffView;
begin
  if ADecision = TAtlasLinkDecision.Reject then
  begin
    Reject(AId);
    Exit;
  end;
  if not FDiffs.Find(AId, mDiff) then
  begin
    Retire(AId);
    Exit;
  end;
  mTarget := TargetOf(mDiff.Request);
  mError := Apply(mDiff, mChanged);
  if mError <> '' then
  begin
    if FViews.TryGetValue(AId, mView) then
    begin
      if mChanged and FDiffs.Find(AId, mDiff) then
      begin
        mView.ShowLines(TAtlasLinkDiffView.DiffLines(ExtractFileName(mTarget), mDiff.OldText, mDiff.Request.NewText));
      end;
      mView.Reopen;
    end;
    TAtlasIdeHost.Message(mError);
    Exit;
  end;
  FActivity.EditApplied(mTarget, FClients(), GetTickCount64);
  Retire(AId);
  FDiffs.Decide(AId, True, TAtlasIdeLinkEditor.CurrentText(mTarget));
  if ADecision = TAtlasLinkDecision.Edit then
  begin
    TAtlasIdeNavigation.ShowFile(mTarget);
  end;
  TAtlasIdeHost.Message(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.LinkDiffAccepted,
    [ExtractFileName(mTarget)]));
end;

function TAtlasIdeLinkProposals.Apply(const ADiff: TAtlasLinkDiff; out AChanged: Boolean): string;
var
  mTarget: string;
  mCurrent: string;
  mDocument: TAtlasLinkDocument;
begin
  AChanged := False;
  mTarget := TargetOf(ADiff.Request);
  mCurrent := TAtlasIdeLinkEditor.CurrentText(mTarget);
  if mCurrent <> ADiff.OldText then
  begin
    // Die Datei hat sich seit dem Zeigen geändert: neuen Stand zeigen und erneut entscheiden lassen.
    AChanged := True;
    FDiffs.Rebase(ADiff.Id, mCurrent);
    Result := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.LinkDiffChanged, [ExtractFileName(mTarget)]);
    Exit;
  end;
  mDocument := TAtlasIdeLinkEditor.Document(mTarget);
  try
    if not mDocument.Open and not FileExists(mTarget) then
    begin
      // Neue Datei: auf die Platte; der Editor kennt sie noch nicht.
      TAtlasDataFile.Write(mTarget, ADiff.Request.NewText);
      Result := '';
      Exit;
    end;
    Result := ApplyInEditor(TAtlasEditInboxPlan.EditOf(mTarget, ADiff.OldText, ADiff.Request.NewText));
    if (Result = '') and mDocument.Open and not TAtlasIdeLinkEditor.Save(mTarget) then
    begin
      Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LinkDiffNotSaved);
    end;
  except
    on E: Exception do
      Result := E.Message;
  end;
  if Result <> '' then
  begin
    Result := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.LinkDiffFailed, [ExtractFileName(mTarget), Result]);
  end;
end;

procedure TAtlasIdeLinkProposals.Reject(AId: Integer);
var
  mDiff: TAtlasLinkDiff;
begin
  Retire(AId);
  if FDiffs.Find(AId, mDiff) and FDiffs.Decide(AId, False, '') then
  begin
    TAtlasIdeHost.Message(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.LinkDiffRejected,
      [ExtractFileName(TargetOf(mDiff.Request))]));
  end;
end;

procedure TAtlasIdeLinkProposals.Retire(AId: Integer);
var
  mView: TAtlasLinkDiffView;
begin
  if not FViews.TryGetValue(AId, mView) then
  begin
    Exit;
  end;
  FViews.Remove(AId);
  mView.OnDecide := nil;
  mView.Hide;
  // Freigegeben im nächsten Takt: Das Fenster kann gerade in seinem eigenen Ereignis sein.
  FRetired.Add(mView);
end;

function TAtlasIdeLinkProposals.Close(const AIds: TArray<Integer>): Integer;
var
  mId: Integer;
begin
  Result := 0;
  for mId in AIds do
  begin
    Retire(mId);
    if FDiffs.Decide(mId, False, '') then
    begin
      Inc(Result);
    end;
  end;
end;

end.
