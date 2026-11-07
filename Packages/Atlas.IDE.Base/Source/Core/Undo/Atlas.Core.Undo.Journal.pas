unit Atlas.Core.Undo.Journal;

// Dateiübergreifendes Änderungsprotokoll von Atlas (#721), ohne VCL und Open
// Tools API.
// - Add protokolliert eine Aktion als Satz, wenn sie mehr als eine Datei
//   ändert oder Dateien anlegt bzw. löscht; unveränderte Dateien fallen weg.
//   Gemerkt werden höchstens Depth Sätze (undo.multiFile.depth).
// - Undo nimmt einen Satz in allen Dateien auf einmal zurück, Redo wendet ihn
//   erneut an. Geprüft wird vorher jede Datei: Sind die Stellen des Satzes
//   seitdem geändert (TAtlasLinePatch), die anzulegende Datei schon da oder
//   die zu ändernde weg, ist das ein Konflikt. Mit Partial werden nur die
//   Dateien ohne Konflikt geschrieben, mit Abort keine. Ein älterer Satz geht
//   genauso, solange seine Stellen unverändert sind.
// - Neu angelegte Dateien trägt das Ziel beim Zurücknehmen aus dem Projekt aus
//   und löscht sie nach NewFiles; gelöschte legt es wieder an.
// - Kodierung: Hat die Aktion die Kodierung nicht geändert, bleibt die
//   aktuelle; sonst kehrt die alte zurück. Zeilenenden stehen im Text.
// - Mit Store wird jeder geänderte Satz sofort gesichert (undo.multiFile.persist).
// - Das Protokoll (OnLog) enthält nur Kennung, Anzahlen und Art, nie Dateinamen
//   oder Quelltext (#647).
// Nur aus einem Thread verwenden (in der IDE der Hauptthread).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Undo.Contract;

type
  TAtlasUndoOptions = record
  public const
    cMinDepth = 1;
    cMaxDepth = 200;
  public
    /// <summary>undo.multiFile: aus = nichts protokollieren, Zurücknehmen meldet Disabled.</summary>
    Enabled: Boolean;
    /// <summary>undo.multiFile.depth.</summary>
    Depth: Integer;
    OnConflict: TAtlasUndoConflictMode;
    NewFiles: TAtlasNewFilesMode;
    class function Defaults: TAtlasUndoOptions; static;
  end;

  TAtlasUndoJournal = class
  private type
{$SCOPEDENUMS ON}
    TPlanKind = (Write, CreateFile, RemoveFile, Nothing);
{$SCOPEDENUMS OFF}
    TPlan = record
      Index: Integer;
      Kind: TPlanKind;
      Content: TAtlasTextFileContent;
    end;
  private
    FTarget: IAtlasUndoTarget;
    FStore: IAtlasUndoStore;
    FSets: TList<TAtlasChangeSet>;
    FRedoStack: TList<Integer>;
    FNextId: Integer;
    FOptions: TAtlasUndoOptions;
    FOnLog: TProc<string>;
    FOnChanged: TProc;
    function SetIndex(AId: Integer): Integer;
    function Plan(const AChange: TAtlasFileChange; AIndex: Integer; ARedo: Boolean; out APlan: TPlan;
      out AProblem: TAtlasUndoProblem): Boolean;
    function Run(AId: Integer; ARedo: Boolean): TAtlasUndoReport;
    procedure Trim;
    procedure Log(const AText: string);
    procedure Changed;
    procedure SetOptions(const AValue: TAtlasUndoOptions);
  public
    constructor Create(const ATarget: IAtlasUndoTarget);
    destructor Destroy; override;
    /// <summary>Protokolliert eine Aktion; Kennung des Satzes oder 0, wenn nichts protokolliert wurde
    /// (ausgeschaltet, nur eine geänderte Datei ohne Anlegen/Löschen, nichts geändert).</summary>
    function Add(const AAction: string; const AFiles: TArray<TAtlasFileChange>): Integer; overload;
    function Add(const AAction: string; const AFiles: TArray<TAtlasFileChange>; ATime: TDateTime): Integer;
      overload;
    /// <summary>Gemerkte Sätze, neueste zuerst.</summary>
    function Sets: TArray<TAtlasChangeSet>;
    function Find(AId: Integer; out ASet: TAtlasChangeSet): Boolean;
    function Count: Integer;
    /// <summary>Neuester Satz, der nicht ganz zurückgenommen ist; 0 = keiner.</summary>
    function LastUndoable: Integer;
    /// <summary>Zuletzt zurückgenommener Satz, der noch zurückgenommene Dateien hat; 0 = keiner. Eine neue
    /// Aktion leert diese Liste (die Sätze bleiben über ihre Kennung erreichbar).</summary>
    function LastRedoable: Integer;
    /// <summary>Letzten Satz zurücknehmen (Strg+Alt+Z).</summary>
    function Undo: TAtlasUndoReport; overload;
    function Undo(AId: Integer): TAtlasUndoReport; overload;
    /// <summary>Zuletzt zurückgenommenen Satz wiederherstellen (Strg+Alt+Umschalt+Z).</summary>
    function Redo: TAtlasUndoReport; overload;
    function Redo(AId: Integer): TAtlasUndoReport; overload;
    /// <summary>Gesicherte Sätze aus dem Speicher laden (nach dem Start); ersetzt die gemerkten.</summary>
    procedure Load;
    procedure Clear;
    /// <summary>Unterschied einer Datei eines Satzes: Zeilen wie TAtlasTextDiff
    /// („- “ vorher, „+ “ nachher).</summary>
    class function Diff(const AChange: TAtlasFileChange): TArray<string>; static;
    property Options: TAtlasUndoOptions read FOptions write SetOptions;
    /// <summary>nil = nicht sichern.</summary>
    property Store: IAtlasUndoStore read FStore write FStore;
    /// <summary>Zeile für das Plugin-Protokoll, ohne Namen und Quelltext.</summary>
    property OnLog: TProc<string> read FOnLog write FOnLog;
    /// <summary>Nach jeder Änderung der Liste (für die Anzeige im Ergebnisfenster).</summary>
    property OnChanged: TProc read FOnChanged write FOnChanged;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Files.TextDiff,
  Atlas.Core.Undo.LinePatch;

{ TAtlasUndoOptions }

class function TAtlasUndoOptions.Defaults: TAtlasUndoOptions;
begin
  Result.Enabled := True;
  Result.Depth := 20;
  Result.OnConflict := TAtlasUndoConflictMode.Partial;
  Result.NewFiles := TAtlasNewFilesMode.RecycleBin;
end;

{ TAtlasUndoJournal }

constructor TAtlasUndoJournal.Create(const ATarget: IAtlasUndoTarget);
begin
  inherited Create;
  FTarget := ATarget;
  FSets := TList<TAtlasChangeSet>.Create;
  FRedoStack := TList<Integer>.Create;
  FNextId := 1;
  FOptions := TAtlasUndoOptions.Defaults;
end;

destructor TAtlasUndoJournal.Destroy;
begin
  FRedoStack.Free;
  FSets.Free;
  inherited;
end;

procedure TAtlasUndoJournal.Log(const AText: string);
begin
  if Assigned(FOnLog) then
  begin
    FOnLog(AText);
  end;
end;

procedure TAtlasUndoJournal.Changed;
begin
  if Assigned(FOnChanged) then
  begin
    FOnChanged();
  end;
end;

procedure TAtlasUndoJournal.SetOptions(const AValue: TAtlasUndoOptions);
begin
  FOptions := AValue;
  FOptions.Depth := EnsureRange(FOptions.Depth, TAtlasUndoOptions.cMinDepth, TAtlasUndoOptions.cMaxDepth);
  Trim;
end;

procedure TAtlasUndoJournal.Trim;
var
  mDropped: Boolean;
begin
  mDropped := False;
  while FSets.Count > FOptions.Depth do
  begin
    if FStore <> nil then
    begin
      FStore.Delete(FSets[0].Id);
    end;
    FRedoStack.Remove(FSets[0].Id);
    FSets.Delete(0);
    mDropped := True;
  end;
  if mDropped then
  begin
    Changed;
  end;
end;

function TAtlasUndoJournal.Add(const AAction: string; const AFiles: TArray<TAtlasFileChange>): Integer;
begin
  Result := Add(AAction, AFiles, Now);
end;

function TAtlasUndoJournal.Add(const AAction: string; const AFiles: TArray<TAtlasFileChange>;
  ATime: TDateTime): Integer;
var
  mChangeSet: TAtlasChangeSet;
  mChange: TAtlasFileChange;
  mFileOps: Boolean;
begin
  Result := 0;
  if not FOptions.Enabled then
  begin
    Exit;
  end;
  mChangeSet := Default(TAtlasChangeSet);
  mFileOps := False;
  for mChange in AFiles do
  begin
    if (mChange.Kind = TAtlasFileChangeKind.Modified) and (mChange.Before.Text = mChange.After.Text) and
      (mChange.Before.Encoding = mChange.After.Encoding) then
    begin
      Continue;
    end;
    if mChange.Kind <> TAtlasFileChangeKind.Modified then
    begin
      mFileOps := True;
    end;
    mChangeSet.Files := mChangeSet.Files + [mChange];
    mChangeSet.Files[High(mChangeSet.Files)].Undone := False;
  end;
  // Eine einzelne geänderte Datei nimmt Strg+Z im Puffer zurück.
  if (Length(mChangeSet.Files) = 0) or ((Length(mChangeSet.Files) = 1) and not mFileOps) then
  begin
    Exit;
  end;
  mChangeSet.Id := FNextId;
  Inc(FNextId);
  mChangeSet.Action := AAction;
  mChangeSet.Time := ATime;
  FSets.Add(mChangeSet);
  FRedoStack.Clear;
  if FStore <> nil then
  begin
    FStore.Save(mChangeSet);
  end;
  Log(Format('Atlas-Änderung #%d protokolliert: %d Dateien', [mChangeSet.Id, Length(mChangeSet.Files)]));
  Trim;
  Changed;
  Result := mChangeSet.Id;
end;

function TAtlasUndoJournal.SetIndex(AId: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to FSets.Count - 1 do
  begin
    if FSets[mIndex].Id = AId then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasUndoJournal.Sets: TArray<TAtlasChangeSet>;
var
  mIndex: Integer;
begin
  SetLength(Result, FSets.Count);
  for mIndex := 0 to FSets.Count - 1 do
  begin
    Result[mIndex] := FSets[FSets.Count - 1 - mIndex];
  end;
end;

function TAtlasUndoJournal.Find(AId: Integer; out ASet: TAtlasChangeSet): Boolean;
var
  mIndex: Integer;
begin
  mIndex := SetIndex(AId);
  Result := mIndex >= 0;
  if Result then
  begin
    ASet := FSets[mIndex];
  end
  else
  begin
    ASet := Default(TAtlasChangeSet);
  end;
end;

function TAtlasUndoJournal.Count: Integer;
begin
  Result := FSets.Count;
end;

function TAtlasUndoJournal.LastUndoable: Integer;
var
  mIndex: Integer;
begin
  for mIndex := FSets.Count - 1 downto 0 do
  begin
    if FSets[mIndex].State <> TAtlasChangeSetState.Undone then
    begin
      Exit(FSets[mIndex].Id);
    end;
  end;
  Result := 0;
end;

function TAtlasUndoJournal.LastRedoable: Integer;
var
  mIndex: Integer;
  mChangeSet: TAtlasChangeSet;
begin
  for mIndex := FRedoStack.Count - 1 downto 0 do
  begin
    if Find(FRedoStack[mIndex], mChangeSet) and (mChangeSet.State <> TAtlasChangeSetState.Applied) then
    begin
      Exit(mChangeSet.Id);
    end;
  end;
  Result := 0;
end;

function TAtlasUndoJournal.Undo: TAtlasUndoReport;
begin
  Result := Undo(LastUndoable);
end;

function TAtlasUndoJournal.Undo(AId: Integer): TAtlasUndoReport;
begin
  Result := Run(AId, False);
end;

function TAtlasUndoJournal.Redo: TAtlasUndoReport;
begin
  Result := Redo(LastRedoable);
end;

function TAtlasUndoJournal.Redo(AId: Integer): TAtlasUndoReport;
begin
  Result := Run(AId, True);
end;

function Verb(ARedo: Boolean): string;
begin
  if ARedo then
  begin
    Result := 'wiederhergestellt';
  end
  else
  begin
    Result := 'zurückgenommen';
  end;
end;

function SameEncoding(const A, B: TAtlasTextFileContent): Boolean;
begin
  Result := (A.Encoding = B.Encoding) and (A.CodePage = B.CodePage);
end;

/// <summary>Zurücknehmen: nachher → vorher; Wiederherstellen umgekehrt. Anlegen und Löschen tauschen dabei die
/// Rollen.</summary>
function Direction(const AChange: TAtlasFileChange; ARedo: Boolean;
  out ASource, ATarget: TAtlasTextFileContent): TAtlasFileChangeKind;
begin
  if ARedo then
  begin
    ASource := AChange.Before;
    ATarget := AChange.After;
    Result := AChange.Kind;
  end
  else
  begin
    ASource := AChange.After;
    ATarget := AChange.Before;
    case AChange.Kind of
      TAtlasFileChangeKind.Created:
        Result := TAtlasFileChangeKind.Deleted;
      TAtlasFileChangeKind.Deleted:
        Result := TAtlasFileChangeKind.Created;
    else
      Result := TAtlasFileChangeKind.Modified;
    end;
  end;
end;

function PlanCreate(AExists: Boolean; const ACurrent, ATarget: TAtlasTextFileContent;
  var APlan: TAtlasUndoJournal.TPlan; var AProblem: TAtlasUndoProblem): Boolean;
begin
  // Schon genau so da (z. B. von Hand wiederhergestellt): nichts zu tun.
  Result := not AExists or (ACurrent.Text = ATarget.Text);
  if not Result then
  begin
    AProblem.Kind := TAtlasUndoProblemKind.Exists;
  end
  else if not AExists then
  begin
    APlan.Kind := TAtlasUndoJournal.TPlanKind.CreateFile;
    APlan.Content := ATarget;
  end;
end;

function PlanRemove(AExists: Boolean; const ACurrent, ASource: TAtlasTextFileContent;
  var APlan: TAtlasUndoJournal.TPlan; var AProblem: TAtlasUndoProblem): Boolean;
begin
  Result := True;
  if not AExists then
  begin
    Exit;
  end;
  // Die ganze Datei ist die Änderung: Jede spätere Änderung ist ein Konflikt.
  Result := ACurrent.Text = ASource.Text;
  if Result then
  begin
    APlan.Kind := TAtlasUndoJournal.TPlanKind.RemoveFile;
  end
  else
  begin
    AProblem.Kind := TAtlasUndoProblemKind.ChangedSince;
  end;
end;

function PlanModify(const ACurrent, ASource, ATarget: TAtlasTextFileContent;
  var APlan: TAtlasUndoJournal.TPlan; var AProblem: TAtlasUndoProblem): Boolean;
var
  mText: string;
begin
  Result := TAtlasLinePatch.Rebase(ASource.Text, ATarget.Text, ACurrent.Text, mText);
  if not Result then
  begin
    AProblem.Kind := TAtlasUndoProblemKind.ChangedSince;
    Exit;
  end;
  APlan.Content := ACurrent;
  APlan.Content.Text := mText;
  if not SameEncoding(ASource, ATarget) and SameEncoding(ACurrent, ASource) then
  begin
    APlan.Content.Encoding := ATarget.Encoding;
    APlan.Content.CodePage := ATarget.CodePage;
  end;
  if (mText <> ACurrent.Text) or not SameEncoding(APlan.Content, ACurrent) then
  begin
    APlan.Kind := TAtlasUndoJournal.TPlanKind.Write;
  end;
end;

function TAtlasUndoJournal.Plan(const AChange: TAtlasFileChange; AIndex: Integer; ARedo: Boolean;
  out APlan: TPlan; out AProblem: TAtlasUndoProblem): Boolean;
var
  mCurrent, mSource, mTarget: TAtlasTextFileContent;
  mExists: Boolean;
  mKind: TAtlasFileChangeKind;
begin
  APlan := Default(TPlan);
  APlan.Index := AIndex;
  APlan.Kind := TPlanKind.Nothing;
  AProblem := Default(TAtlasUndoProblem);
  AProblem.FileName := AChange.FileName;
  mKind := Direction(AChange, ARedo, mSource, mTarget);
  try
    mExists := FTarget.Read(AChange.FileName, mCurrent);
  except
    on E: Exception do
    begin
      AProblem.Kind := TAtlasUndoProblemKind.Failed;
      AProblem.Message := E.Message;
      Exit(False);
    end;
  end;
  case mKind of
    TAtlasFileChangeKind.Created:
      Result := PlanCreate(mExists, mCurrent, mTarget, APlan, AProblem);
    TAtlasFileChangeKind.Deleted:
      Result := PlanRemove(mExists, mCurrent, mSource, APlan, AProblem);
  else
    Result := mExists;
    if Result then
    begin
      Result := PlanModify(mCurrent, mSource, mTarget, APlan, AProblem);
    end
    else
    begin
      AProblem.Kind := TAtlasUndoProblemKind.Missing;
    end;
  end;
end;

/// <summary>1. Prüfen: alle betroffenen Dateien lesen, noch nichts ändern. Zurücknehmen betrifft die noch
/// angewendeten Dateien, Wiederherstellen die zurückgenommenen.</summary>
function CheckFiles(AJournal: TAtlasUndoJournal; const AChangeSet: TAtlasChangeSet; ARedo: Boolean;
  var AReport: TAtlasUndoReport): TArray<TAtlasUndoJournal.TPlan>;
var
  mIndex: Integer;
  mPlanned: TAtlasUndoJournal.TPlan;
  mProblem: TAtlasUndoProblem;
begin
  Result := nil;
  for mIndex := 0 to High(AChangeSet.Files) do
  begin
    if AChangeSet.Files[mIndex].Undone <> ARedo then
    begin
      Continue;
    end;
    if AJournal.Plan(AChangeSet.Files[mIndex], mIndex, ARedo, mPlanned, mProblem) then
    begin
      Result := Result + [mPlanned];
    end
    else if mProblem.Kind = TAtlasUndoProblemKind.Failed then
    begin
      AReport.Errors := AReport.Errors + [mProblem];
    end
    else
    begin
      AReport.Conflicts := AReport.Conflicts + [mProblem];
    end;
  end;
end;

/// <summary>Einen Plan ausführen; Fehler kommen als Ausnahme.</summary>
procedure ApplyPlan(const ATarget: IAtlasUndoTarget; const APlan: TAtlasUndoJournal.TPlan;
  const AChange: TAtlasFileChange; ARedo: Boolean; ANewFiles: TAtlasNewFilesMode);
begin
  case APlan.Kind of
    TAtlasUndoJournal.TPlanKind.Write:
      ATarget.Write(AChange.FileName, APlan.Content);
    TAtlasUndoJournal.TPlanKind.CreateFile:
      ATarget.CreateFile(AChange.FileName, AChange.Project, APlan.Content);
    TAtlasUndoJournal.TPlanKind.RemoveFile:
      begin
        // Eine beim Wiederherstellen erneut gelöschte Datei bleibt nie liegen; ihr Inhalt steht im Satz.
        if ARedo and (ANewFiles = TAtlasNewFilesMode.Keep) then
        begin
          ANewFiles := TAtlasNewFilesMode.RecycleBin;
        end;
        ATarget.RemoveFile(AChange.FileName, AChange.Project, ANewFiles);
      end;
  end;
end;

/// <summary>2. Schreiben: jede Datei für sich; ein Fehler hält die anderen nicht auf. True, wenn eine Datei
/// geändert wurde.</summary>
function ApplyPlans(const ATarget: IAtlasUndoTarget; ANewFiles: TAtlasNewFilesMode;
  const APlans: TArray<TAtlasUndoJournal.TPlan>; ARedo: Boolean; var AChangeSet: TAtlasChangeSet;
  var AReport: TAtlasUndoReport): Boolean;
var
  mPlanned: TAtlasUndoJournal.TPlan;
  mChange: TAtlasFileChange;
  mProblem: TAtlasUndoProblem;
begin
  Result := False;
  for mPlanned in APlans do
  begin
    mChange := AChangeSet.Files[mPlanned.Index];
    try
      ApplyPlan(ATarget, mPlanned, mChange, ARedo, ANewFiles);
    except
      on E: Exception do
      begin
        mProblem := Default(TAtlasUndoProblem);
        mProblem.FileName := mChange.FileName;
        mProblem.Kind := TAtlasUndoProblemKind.Failed;
        mProblem.Message := E.Message;
        AReport.Errors := AReport.Errors + [mProblem];
        Continue;
      end;
    end;
    AChangeSet.Files[mPlanned.Index].Undone := not ARedo;
    AReport.Done := AReport.Done + [mChange.FileName];
    Result := True;
  end;
end;

function TAtlasUndoJournal.Run(AId: Integer; ARedo: Boolean): TAtlasUndoReport;
var
  mSetPosition: Integer;
  mChangeSet: TAtlasChangeSet;
  mPlans: TArray<TPlan>;
  mTouched, mTrouble: Boolean;
begin
  Result := Default(TAtlasUndoReport);
  Result.SetId := AId;
  Result.Redo := ARedo;
  Result.Disabled := not FOptions.Enabled;
  mSetPosition := -1;
  if not Result.Disabled then
  begin
    mSetPosition := SetIndex(AId);
  end;
  Result.NotFound := not Result.Disabled and (mSetPosition < 0);
  if Result.Disabled or Result.NotFound then
  begin
    Exit;
  end;
  mChangeSet := FSets[mSetPosition];
  Result.Action := mChangeSet.Action;
  mPlans := CheckFiles(Self, mChangeSet, ARedo, Result);
  mTrouble := (Length(Result.Conflicts) > 0) or (Length(Result.Errors) > 0);
  Result.NotFound := (Length(mPlans) = 0) and not mTrouble;
  Result.Aborted := mTrouble and (FOptions.OnConflict = TAtlasUndoConflictMode.Abort);
  if Result.Aborted then
  begin
    Log(Format('Atlas-Änderung #%d nicht %s: %d Konflikte, %d Fehler, abgebrochen',
      [AId, Verb(ARedo), Length(Result.Conflicts), Length(Result.Errors)]));
  end;
  if Result.NotFound or Result.Aborted then
  begin
    Exit;
  end;
  mTouched := ApplyPlans(FTarget, FOptions.NewFiles, mPlans, ARedo, mChangeSet, Result);
  FSets[mSetPosition] := mChangeSet;
  if mTouched then
  begin
    FRedoStack.Remove(AId);
    if not ARedo or (mChangeSet.State <> TAtlasChangeSetState.Applied) then
    begin
      FRedoStack.Add(AId);
    end;
    if FStore <> nil then
    begin
      FStore.Save(mChangeSet);
    end;
  end;
  Log(Format('Atlas-Änderung #%d %s: %d Dateien, %d Konflikte, %d Fehler',
    [AId, Verb(ARedo), Length(Result.Done), Length(Result.Conflicts), Length(Result.Errors)]));
  if mTouched then
  begin
    Changed;
  end;
end;

procedure TAtlasUndoJournal.Load;
var
  mLoaded: TArray<TAtlasChangeSet>;
  mChangeSet: TAtlasChangeSet;
begin
  if FStore = nil then
  begin
    Exit;
  end;
  mLoaded := FStore.Load;
  FSets.Clear;
  FRedoStack.Clear;
  for mChangeSet in mLoaded do
  begin
    FSets.Add(mChangeSet);
    FNextId := Max(FNextId, mChangeSet.Id + 1);
  end;
  Log(Format('Atlas-Änderungsprotokoll geladen: %d Sätze', [FSets.Count]));
  Trim;
  Changed;
end;

procedure TAtlasUndoJournal.Clear;
begin
  FSets.Clear;
  FRedoStack.Clear;
  if FStore <> nil then
  begin
    FStore.Clear;
  end;
  Changed;
end;

class function TAtlasUndoJournal.Diff(const AChange: TAtlasFileChange): TArray<string>;
begin
  Result := TAtlasTextDiff.Lines(AChange.Before.Text, AChange.After.Text);
end;

end.
