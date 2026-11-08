unit Atlas.IDE.VersionControl.LineChangesData;

// Stand der Änderungsmarken und der Zeilenhistorie (#507) für die Datei im
// oberen Editor: Arbeitskopie (TAtlasIdeVcs, #571), Stand im Repository
// (FileAt), Vergleich mit dem Puffer nach einer Tipp-Pause, blame der Datei
// auf der Platte samt Zuordnung Platte → Puffer und ganzen Nachrichten
// (#1275, über TAtlasLineChangesHooks). Alles Langsame läuft über
// TAtlasIdeVcs.Run im Hintergrund; jede Arbeit merkt sich die Generation,
// nach Reset oder Freigabe verfällt ihr Ergebnis. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  ToolsAPI,
  Atlas.Text.Diff,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.Editor.LineChanges;

type
  /// <summary>Ganze Nachrichten zu den Revisionen aus blame; läuft im Hintergrund.</summary>
  TAtlasLineMessagesFunc = reference to function(const AVcs: IAtlasVersionControl; const AFileName: string;
    const ALines: TArray<TAtlasVcsBlameLine>): TArray<TAtlasVcsRevisionMessage>;

  /// <summary>Ergänzungen der Zeilenhistorie (#1275), von der Komposition über TAtlasIdeLineChanges.</summary>
  TAtlasLineChangesHooks = record
    /// <summary>Ganze Nachrichten laden? (Hauptthread)</summary>
    Wanted: TFunc<Boolean>;
    /// <summary>Lader der Nachrichten; im Hauptthread geholt, läuft im Hintergrund.</summary>
    Loader: TFunc<TAtlasLineMessagesFunc>;
    /// <summary>Anhang hinter der Zeit (" · ATL-97") zur Nachricht; '' ohne.</summary>
    Suffix: TFunc<string, string>;
  end;

  TAtlasIdeLineChangesData = class
  private type
    /// <summary>Stand im Repository; Ok erst nach erfolgreichem FileAt.</summary>
    THead = record
      Lines: TArray<string>;
      Ok: Boolean;
      Wanted: Boolean;
      Busy: Boolean;
    end;
    /// <summary>Ergebnis des letzten Vergleichs und der Text, zu dem es gehört.</summary>
    TDiff = record
      Text: string;
      Busy: Boolean;
      Lines: TArray<string>;
      LineBreak: string;
      Changes: TAtlasLineChangeList;
      Shown: Boolean;
    end;
    /// <summary>Zeilenhistorie der Datei auf der Platte und ihre Zuordnung zum Puffer.</summary>
    TBlame = record
      Lines: TArray<TAtlasVcsBlameLine>;
      Disk: TArray<string>;
      DiskHunks: TArray<TTextLineHunk>;
      Ok: Boolean;
      Wanted: Boolean;
      Busy: Boolean;
      /// <summary>Waren die ganzen Nachrichten zum letzten blame gewollt?</summary>
      MessagesWanted: Boolean;
    end;
  private
    FHooks: TAtlasLineChangesHooks;
    FFileName: string;
    FVcs: IAtlasVersionControl;
    FText: string;
    FChangedAt: UInt64;
    FPolledAt: UInt64;
    FMarker: string;
    FDiskAge: TDateTime;
    FHead: THead;
    FDiff: TDiff;
    FBlame: TBlame;
    // Ganze Nachrichten je Revision (#1275).
    FMessages: TDictionary<string, string>;
    function MessagesWanted: Boolean;
    /// <summary>Arbeitskopie suchen (einmal je PollMs); True, wenn es eine gibt.</summary>
    function Attach: Boolean;
    procedure Poll;
    /// <summary>Fällige Arbeit im Hintergrund starten.</summary>
    procedure Load(ABlameOn: Boolean);
    procedure LoadHead;
    procedure LoadBlame;
    /// <summary>Ergebnis von blame übernehmen (Hauptthread).</summary>
    procedure StoreBlame(AOk: Boolean; const ABlame: TArray<TAtlasVcsBlameLine>; const ADisk: TArray<string>;
      AWanted: Boolean; const AMessages: TArray<TAtlasVcsRevisionMessage>);
    procedure Compare;
    /// <summary>Eintrag von blame für Zeile ADiskLine (0-basiert) der Platte; -1 ohne.</summary>
    function EntryOf(ADiskLine: Integer): Integer;
  public
    constructor Create(const AHooks: TAtlasLineChangesHooks);
    destructor Destroy; override;
    /// <summary>Generation der Hintergrundarbeit; ändert sich mit Reset und Freigabe.</summary>
    class function Generation: Integer; static;
    /// <summary>Alles vergessen; laufende Ergebnisse verfallen.</summary>
    procedure Reset;
    /// <summary>Nach Reset: Datei von AView beobachten.</summary>
    procedure Start(const AView: IOTAEditView);
    /// <summary>Nach jedem Takt: Änderungen merken, Fälliges laden; True, wenn sich der Text geändert hat.</summary>
    function Track(const AView: IOTAEditView; AGutterOn, ABlameOn: Boolean): Boolean;
    /// <summary>Gehört der letzte Vergleich zum Text im Puffer?</summary>
    function Fresh: Boolean;
    /// <summary>Text der Randanzeige für Pufferzeile ABufferLine; AEntry: Eintrag von blame (-1 ohne), AUnsaved:
    /// Zeile nicht gespeichert.</summary>
    function BlameCaption(ABufferLine: Integer; out AEntry: Integer; out AUnsaved: Boolean): string;
    /// <summary>Ganze Nachricht, sofern geladen, sonst der Betreff aus blame.</summary>
    function MessageOf(const AEntry: TAtlasVcsBlameLine): string;
    /// <summary>Text des Hovers zum Commit: Autor, Datum (Ortszeit) und Betreff.</summary>
    class function CommitText(const AEntry: TAtlasVcsBlameLine): string; static;
    function HasEntry(AIndex: Integer): Boolean;
    function Entry(AIndex: Integer): TAtlasVcsBlameLine;
    function VcsKind: TAtlasVcsKind;
    function LineCount: Integer;
    /// <summary>Änderung AChange auf den Stand im Repository zurücksetzen (ein Rückgängig-Schritt im Puffer);
    /// AError: Meldung, wenn das scheitert. False, wenn der Vergleich nicht mehr gilt.</summary>
    function Revert(AChange: Integer; out AError: string): Boolean;
    property FileName: string read FFileName;
    property Changes: TAtlasLineChangeList read FDiff.Changes;
    property HeadOk: Boolean read FHead.Ok;
    property BlameOk: Boolean read FBlame.Ok;
  end;

implementation

uses
  ToolsAPI.Editor,
  System.Classes,
  System.DateUtils,
  Atlas.Text.Lines,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.UI.Strings,
  Atlas.UI.VersionControl.Strings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorRefresh,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Contracts.VersionControl;

const
  /// <summary>Tipp-Pause vor dem Vergleich.</summary>
  cQuietMs = 300;
  /// <summary>So oft prüft Atlas Commit (ChangeMarker) und Speichern (Zeitstempel der Datei).</summary>
  cPollMs = 1000;

var
  // Jede Hintergrundarbeit merkt sich die Generation; nach Reset oder Freigabe verfällt ihr Ergebnis.
  GGeneration: Integer;

procedure Invalidate;
var
  mServices: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mServices);
  end;
end;

function AgeText(const AAge: TAtlasAge): string;
begin
  case AAge.Unit_ of
    TAtlasAgeUnit.Minutes:
      Result := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.BlameMinutes, [AAge.Count]);
    TAtlasAgeUnit.Hours:
      Result := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.BlameHours, [AAge.Count]);
    TAtlasAgeUnit.Yesterday:
      Result := TAtlasVcsStrings.Text(TAtlasVcsTextId.BlameYesterday);
    TAtlasAgeUnit.Days:
      Result := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.BlameDays, [AAge.Count]);
    TAtlasAgeUnit.Months:
      Result := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.BlameMonths, [AAge.Count]);
    TAtlasAgeUnit.Years:
      Result := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.BlameYears, [AAge.Count]);
  else
    Result := TAtlasVcsStrings.Text(TAtlasVcsTextId.BlameJustNow);
  end;
  // Ein Monat bzw. ein Jahr im Singular.
  if (AAge.Count = 1) and (AAge.Unit_ = TAtlasAgeUnit.Months) then
  begin
    Result := TAtlasVcsStrings.Text(TAtlasVcsTextId.BlameMonth);
  end
  else if (AAge.Count = 1) and (AAge.Unit_ = TAtlasAgeUnit.Years) then
  begin
    Result := TAtlasVcsStrings.Text(TAtlasVcsTextId.BlameYear);
  end;
end;

/// <summary>„Autor, vor 3 Tagen · Betreff“; ASuffix hinter der Zeit (#1275).</summary>
function EntryCaption(const AEntry: TAtlasVcsBlameLine; const ASuffix: string): string;
var
  mAge: string;
begin
  mAge := AgeText(TAtlasLineChanges.Age(TTimeZone.Local.ToUniversalTime(Now), AEntry.Date)) + ASuffix;
  // SVN liefert keinen Betreff.
  if AEntry.Summary = '' then
  begin
    Result := AEntry.Author + ', ' + mAge;
  end
  else
  begin
    Result := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.BlameLine, [AEntry.Author, mAge, AEntry.Summary]);
  end;
end;

{ TAtlasIdeLineChangesData }

constructor TAtlasIdeLineChangesData.Create(const AHooks: TAtlasLineChangesHooks);
begin
  inherited Create;
  Inc(GGeneration);
  FHooks := AHooks;
  FMessages := TDictionary<string, string>.Create;
end;

destructor TAtlasIdeLineChangesData.Destroy;
begin
  // Ergebnisse, die noch unterwegs sind, verfallen.
  Inc(GGeneration);
  FMessages.Free;
  inherited Destroy;
end;

class function TAtlasIdeLineChangesData.Generation: Integer;
begin
  Result := GGeneration;
end;

procedure TAtlasIdeLineChangesData.Reset;
var
  mShown: Boolean;
begin
  Inc(GGeneration);
  mShown := FDiff.Shown;
  FFileName := '';
  FVcs := nil;
  FText := '';
  FMarker := '';
  FDiskAge := 0;
  FHead := Default(THead);
  FDiff := Default(TDiff);
  FBlame := Default(TBlame);
  FMessages.Clear;
  if mShown then
  begin
    Invalidate;
  end;
end;

procedure TAtlasIdeLineChangesData.Start(const AView: IOTAEditView);
begin
  FFileName := AView.Buffer.FileName;
  FText := TAtlasEditorBuffer.Text(AView.Buffer);
  FChangedAt := 0;
  FPolledAt := 0;
end;

function TAtlasIdeLineChangesData.Fresh: Boolean;
begin
  Result := FHead.Ok and (FDiff.Text = FText) and (FDiff.Lines <> nil);
end;

function TAtlasIdeLineChangesData.MessagesWanted: Boolean;
begin
  Result := Assigned(FHooks.Wanted) and FHooks.Wanted();
end;

function TAtlasIdeLineChangesData.Attach: Boolean;
begin
  // Prüft nur Dateien; einmal je PollMs, damit ein späteres git init oder der Start der Versionsverwaltung greift.
  Result := False;
  if TThread.GetTickCount64 - FPolledAt < cPollMs then
  begin
    Exit;
  end;
  FPolledAt := TThread.GetTickCount64;
  FVcs := TAtlasIdeVcs.ForFolder(ExtractFileDir(FFileName));
  if (FVcs <> nil) and (FVcs.Kind = TAtlasVcsKind.None) then
  begin
    FVcs := nil;
  end;
  Result := FVcs <> nil;
  if Result then
  begin
    FMarker := FVcs.ChangeMarker;
    if not FileAge(FFileName, FDiskAge) then
    begin
      FDiskAge := 0;
    end;
    FHead.Wanted := True;
    FBlame.Wanted := True;
  end;
end;

function TAtlasIdeLineChangesData.Track(const AView: IOTAEditView; AGutterOn, ABlameOn: Boolean): Boolean;
var
  mText: string;
begin
  // Ohne Arbeitskopie bleibt FVcs leer und alles still.
  Result := False;
  if (FVcs = nil) and not Attach then
  begin
    Exit;
  end;
  mText := TAtlasEditorBuffer.Text(AView.Buffer);
  Result := mText <> FText;
  if Result then
  begin
    FText := mText;
    FChangedAt := TThread.GetTickCount64;
  end;
  if TThread.GetTickCount64 - FPolledAt >= cPollMs then
  begin
    Poll;
  end;
  if AGutterOn or ABlameOn then
  begin
    Load(ABlameOn);
  end;
end;

procedure TAtlasIdeLineChangesData.Load(ABlameOn: Boolean);
begin
  if FHead.Wanted and not FHead.Busy then
  begin
    LoadHead;
  end;
  if ABlameOn and FBlame.Wanted and not FBlame.Busy then
  begin
    LoadBlame;
  end;
  if FHead.Ok and not FDiff.Busy and (FText <> FDiff.Text) and
    (TThread.GetTickCount64 - FChangedAt >= cQuietMs) then
  begin
    Compare;
  end;
end;

procedure TAtlasIdeLineChangesData.Poll;
var
  mMarker: string;
  mAge: TDateTime;
begin
  FPolledAt := TThread.GetTickCount64;
  // Commit, Pull oder Wechsel des Branchs: Stand im Repository und Historie neu.
  mMarker := FVcs.ChangeMarker;
  if mMarker <> FMarker then
  begin
    FMarker := mMarker;
    FHead.Wanted := True;
    FBlame.Wanted := True;
  end;
  // Gespeichert: blame liest die Platte.
  if not FileAge(FFileName, mAge) then
  begin
    mAge := 0;
  end;
  if mAge <> FDiskAge then
  begin
    FDiskAge := mAge;
    FBlame.Wanted := True;
  end;
  // Issues in der Zeilenhistorie eingeschaltet oder Tracker jetzt da (#1275): Nachrichten nachladen.
  if FBlame.Ok and not FBlame.MessagesWanted and MessagesWanted then
  begin
    FBlame.Wanted := True;
  end;
end;

procedure TAtlasIdeLineChangesData.LoadHead;
var
  mVcs: IAtlasVersionControl;
  mFileName: string;
  mGen: Integer;
  mOutcome: TAtlasVcsOutcome;
  mLines: TArray<string>;
begin
  FHead.Wanted := False;
  FHead.Busy := True;
  mVcs := FVcs;
  mFileName := FFileName;
  mGen := GGeneration;
  mOutcome := TAtlasVcsOutcome.Failed;
  mLines := nil;
  if not TAtlasIdeVcs.Run(
    procedure
    var
      mBytes: TBytes;
    begin
      mOutcome := mVcs.FileAt(mFileName, '', mBytes);
      if mOutcome = TAtlasVcsOutcome.Ok then
      begin
        mLines := TTextLines.SplitLines(TAtlasTextFile.Decode(mBytes).Text);
      end;
    end,
    procedure
    begin
      // Gleiche Generation: Das Objekt lebt noch und gilt für dieselbe Datei.
      if mGen <> GGeneration then
      begin
        Exit;
      end;
      FHead.Busy := False;
      // Nicht versioniert (oder git meldet einen Fehler): keine Marken.
      FHead.Ok := mOutcome = TAtlasVcsOutcome.Ok;
      FHead.Lines := mLines;
      FDiff.Text := '';
      FDiff.Changes := nil;
      if not FHead.Ok and FDiff.Shown then
      begin
        Invalidate;
      end;
    end) then
  begin
    FHead.Busy := False;
  end;
end;

procedure TAtlasIdeLineChangesData.LoadBlame;
var
  mVcs: IAtlasVersionControl;
  mFileName: string;
  mGen: Integer;
  mOutcome: TAtlasVcsOutcome;
  mBlame: TArray<TAtlasVcsBlameLine>;
  mDisk: TArray<string>;
  mWanted: Boolean;
  mLoader: TAtlasLineMessagesFunc;
  mMessages: TArray<TAtlasVcsRevisionMessage>;
begin
  FBlame.Wanted := False;
  FBlame.Busy := True;
  mVcs := FVcs;
  mFileName := FFileName;
  mGen := GGeneration;
  mOutcome := TAtlasVcsOutcome.Failed;
  mBlame := nil;
  mDisk := nil;
  // Ganze Nachrichten (#1275) nur, wenn die Issues in der Zeilenhistorie sie brauchen.
  mWanted := MessagesWanted;
  mLoader := nil;
  if mWanted and Assigned(FHooks.Loader) then
  begin
    mLoader := FHooks.Loader();
  end;
  mMessages := nil;
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      mOutcome := mVcs.Blame(mFileName, mBlame);
      if mOutcome = TAtlasVcsOutcome.Ok then
      begin
        mDisk := TTextLines.SplitLines(TAtlasTextFile.Load(mFileName).Text);
      end;
      if (mOutcome = TAtlasVcsOutcome.Ok) and Assigned(mLoader) then
      begin
        mMessages := mLoader(mVcs, mFileName, mBlame);
      end;
    end,
    procedure
    begin
      if mGen = GGeneration then
      begin
        StoreBlame(mOutcome = TAtlasVcsOutcome.Ok, mBlame, mDisk, mWanted, mMessages);
      end;
    end) then
  begin
    FBlame.Busy := False;
  end;
end;

procedure TAtlasIdeLineChangesData.StoreBlame(AOk: Boolean; const ABlame: TArray<TAtlasVcsBlameLine>;
  const ADisk: TArray<string>; AWanted: Boolean; const AMessages: TArray<TAtlasVcsRevisionMessage>);
var
  mMessage: TAtlasVcsRevisionMessage;
begin
  FBlame.Busy := False;
  FBlame.Ok := AOk;
  FBlame.Lines := ABlame;
  FBlame.Disk := ADisk;
  FBlame.MessagesWanted := AWanted;
  FMessages.Clear;
  for mMessage in AMessages do
  begin
    FMessages.AddOrSetValue(mMessage.Revision, mMessage.Message);
  end;
  // Zuordnung Platte → Puffer beim nächsten Vergleich neu.
  FDiff.Text := '';
  FBlame.DiskHunks := nil;
end;

procedure TAtlasIdeLineChangesData.Compare;
var
  mHead, mDisk, mLines: TArray<string>;
  mText, mLineBreak: string;
  mGen: Integer;
  mChanges: TAtlasLineChangeList;
  mHunks: TArray<TTextLineHunk>;
begin
  FDiff.Busy := True;
  mHead := FHead.Lines;
  mDisk := FBlame.Disk;
  mText := FText;
  mGen := GGeneration;
  mChanges := nil;
  mHunks := nil;
  mLines := nil;
  mLineBreak := sLineBreak;
  if not TAtlasIdeVcs.Run(
    procedure
    begin
      mLines := TTextLines.SplitLines(mText, mLineBreak);
      mChanges := TAtlasLineChanges.Compute(mHead, mLines);
      if mDisk <> nil then
      begin
        mHunks := TTextDiff.Hunks(mDisk, mLines);
      end;
    end,
    procedure
    begin
      if mGen <> GGeneration then
      begin
        Exit;
      end;
      FDiff.Busy := False;
      FDiff.Text := mText;
      FDiff.Lines := mLines;
      if mLineBreak = '' then
      begin
        mLineBreak := sLineBreak;
      end;
      FDiff.LineBreak := mLineBreak;
      FDiff.Changes := mChanges;
      FBlame.DiskHunks := mHunks;
      FDiff.Shown := True;
      Invalidate;
    end) then
  begin
    FDiff.Busy := False;
  end;
end;

function TAtlasIdeLineChangesData.EntryOf(ADiskLine: Integer): Integer;
var
  mIndex: Integer;
begin
  // blame liefert die Zeilen der Reihe nach; sonst suchen.
  if (ADiskLine <= High(FBlame.Lines)) and (FBlame.Lines[ADiskLine].Line = ADiskLine + 1) then
  begin
    Exit(ADiskLine);
  end;
  Result := -1;
  mIndex := 0;
  while (Result < 0) and (mIndex <= High(FBlame.Lines)) do
  begin
    if FBlame.Lines[mIndex].Line = ADiskLine + 1 then
    begin
      Result := mIndex;
    end;
    Inc(mIndex);
  end;
end;

function TAtlasIdeLineChangesData.BlameCaption(ABufferLine: Integer; out AEntry: Integer;
  out AUnsaved: Boolean): string;
var
  mDiskLine: Integer;
  mEntry: TAtlasVcsBlameLine;
  mSuffix: string;
begin
  Result := '';
  AEntry := -1;
  AUnsaved := False;
  if not FBlame.Ok or (FBlame.Disk = nil) then
  begin
    Exit;
  end;
  mDiskLine := TAtlasLineChanges.BlameLine(FBlame.DiskHunks, ABufferLine);
  AUnsaved := mDiskLine < 0;
  if AUnsaved then
  begin
    Exit(TAtlasVcsStrings.Text(TAtlasVcsTextId.BlameUnsaved));
  end;
  AEntry := EntryOf(mDiskLine);
  if AEntry < 0 then
  begin
    Exit;
  end;
  mEntry := FBlame.Lines[AEntry];
  if mEntry.Uncommitted then
  begin
    Exit(TAtlasVcsStrings.Text(TAtlasVcsTextId.BlameUncommitted));
  end;
  // Kennungen aus der Nachricht hinter der Zeit (#1275), aus dem Speicher, ohne Tracker.
  mSuffix := '';
  if Assigned(FHooks.Suffix) then
  begin
    mSuffix := FHooks.Suffix(MessageOf(mEntry));
  end;
  Result := EntryCaption(mEntry, mSuffix);
end;

class function TAtlasIdeLineChangesData.CommitText(const AEntry: TAtlasVcsBlameLine): string;
begin
  Result := TAtlasVcsStrings.Fmt(TAtlasVcsTextId.BlameCommitText,
    [AEntry.Author, FormatDateTime('dd.mm.yyyy hh":"nn', TTimeZone.Local.ToLocalTime(AEntry.Date)), AEntry.Summary]);
end;

function TAtlasIdeLineChangesData.MessageOf(const AEntry: TAtlasVcsBlameLine): string;
begin
  if not FMessages.TryGetValue(AEntry.Revision, Result) then
  begin
    Result := AEntry.Summary;
  end;
end;

function TAtlasIdeLineChangesData.HasEntry(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(FBlame.Lines));
end;

function TAtlasIdeLineChangesData.Entry(AIndex: Integer): TAtlasVcsBlameLine;
begin
  Result := FBlame.Lines[AIndex];
end;

function TAtlasIdeLineChangesData.VcsKind: TAtlasVcsKind;
begin
  Result := TAtlasVcsKind.None;
  if FVcs <> nil then
  begin
    Result := FVcs.Kind;
  end;
end;

function TAtlasIdeLineChangesData.LineCount: Integer;
begin
  Result := Length(FDiff.Lines);
end;

function TAtlasIdeLineChangesData.Revert(AChange: Integer; out AError: string): Boolean;
var
  mEdit: TLspWorkspaceEdit;
  mFileEdits: TLspFileEdits;
  mLineEdit: TAtlasLineEdit;
  mTextEdit: TLspTextEdit;
begin
  AError := '';
  // Nur zum Stand, den das Fenster gezeigt hat.
  Result := Fresh and (AChange >= 0) and (AChange <= High(FDiff.Changes));
  if not Result then
  begin
    Exit;
  end;
  mLineEdit := TAtlasLineChanges.Revert(FDiff.Changes[AChange], FDiff.Lines, FDiff.LineBreak);
  mTextEdit := Default(TLspTextEdit);
  mTextEdit.StartPos := TLspTextPosition.Create(mLineEdit.StartLine, mLineEdit.StartCharacter);
  mTextEdit.EndPos := TLspTextPosition.Create(mLineEdit.EndLine, mLineEdit.EndCharacter);
  mTextEdit.NewText := mLineEdit.NewText;
  mFileEdits := Default(TLspFileEdits);
  mFileEdits.FileName := FFileName;
  mFileEdits.Edits := [mTextEdit];
  mEdit := Default(TLspWorkspaceEdit);
  mEdit.Files := [mFileEdits];
  // Ein Rückgängig-Schritt im Puffer (#397); Strg+Z stellt die Änderung wieder her.
  AError := TAtlasIdeWorkspaceEdit.Apply(mEdit, TAtlasUnopenedPolicy.OpenInEditor,
    TAtlasVcsStrings.Text(TAtlasVcsTextId.ChangeRevertAction)).Error;
end;

end.
