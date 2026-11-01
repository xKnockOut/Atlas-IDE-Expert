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
    MinDepth = 1;
    MaxDepth = 200;
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
    FOnLog(AText);
end;

procedure TAtlasUndoJournal.Changed;
begin
  if Assigned(FOnChanged) then
    FOnChanged();
end;

procedure TAtlasUndoJournal.SetOptions(const AValue: TAtlasUndoOptions);
begin
  FOptions := AValue;
  FOptions.Depth := EnsureRange(FOptions.Depth, TAtlasUndoOptions.MinDepth, TAtlasUndoOptions.MaxDepth);
  Trim;
end;

procedure TAtlasUndoJournal.Trim;
var
  Dropped: Boolean;
begin
  Dropped := False;
  while FSets.Count > FOptions.Depth do
  begin
    if FStore <> nil then
      FStore.Delete(FSets[0].Id);
    FRedoStack.Remove(FSets[0].Id);
    FSets.Delete(0);
    Dropped := True;
  end;
  if Dropped then
    Changed;
end;

function TAtlasUndoJournal.Add(const AAction: string; const AFiles: TArray<TAtlasFileChange>): Integer;
begin
  Result := Add(AAction, AFiles, Now);
end;

function TAtlasUndoJournal.Add(const AAction: string; const AFiles: TArray<TAtlasFileChange>;
  ATime: TDateTime): Integer;
var
  ChangeSet: TAtlasChangeSet;
  Change: TAtlasFileChange;
  FileOps: Boolean;
begin
  Result := 0;
  if not FOptions.Enabled then
    Exit;
  ChangeSet := Default(TAtlasChangeSet);
  FileOps := False;
  for Change in AFiles do
  begin
    if (Change.Kind = TAtlasFileChangeKind.Modified) and (Change.Before.Text = Change.After.Text) and
      (Change.Before.Encoding = Change.After.Encoding) then
      Continue;
    if Change.Kind <> TAtlasFileChangeKind.Modified then
      FileOps := True;
    ChangeSet.Files := ChangeSet.Files + [Change];
    ChangeSet.Files[High(ChangeSet.Files)].Undone := False;
  end;
  // Eine einzelne geänderte Datei nimmt Strg+Z im Puffer zurück.
  if (Length(ChangeSet.Files) = 0) or ((Length(ChangeSet.Files) = 1) and not FileOps) then
    Exit;
  ChangeSet.Id := FNextId;
  Inc(FNextId);
  ChangeSet.Action := AAction;
  ChangeSet.Time := ATime;
  FSets.Add(ChangeSet);
  FRedoStack.Clear;
  if FStore <> nil then
    FStore.Save(ChangeSet);
  Log(Format('Atlas-Änderung #%d protokolliert: %d Dateien', [ChangeSet.Id, Length(ChangeSet.Files)]));
  Trim;
  Changed;
  Result := ChangeSet.Id;
end;

function TAtlasUndoJournal.SetIndex(AId: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to FSets.Count - 1 do
    if FSets[Index].Id = AId then
      Exit(Index);
  Result := -1;
end;

function TAtlasUndoJournal.Sets: TArray<TAtlasChangeSet>;
var
  Index: Integer;
begin
  SetLength(Result, FSets.Count);
  for Index := 0 to FSets.Count - 1 do
    Result[Index] := FSets[FSets.Count - 1 - Index];
end;

function TAtlasUndoJournal.Find(AId: Integer; out ASet: TAtlasChangeSet): Boolean;
var
  Index: Integer;
begin
  Index := SetIndex(AId);
  Result := Index >= 0;
  if Result then
    ASet := FSets[Index]
  else
    ASet := Default(TAtlasChangeSet);
end;

function TAtlasUndoJournal.Count: Integer;
begin
  Result := FSets.Count;
end;

function TAtlasUndoJournal.LastUndoable: Integer;
var
  Index: Integer;
begin
  for Index := FSets.Count - 1 downto 0 do
    if FSets[Index].State <> TAtlasChangeSetState.Undone then
      Exit(FSets[Index].Id);
  Result := 0;
end;

function TAtlasUndoJournal.LastRedoable: Integer;
var
  Index: Integer;
  ChangeSet: TAtlasChangeSet;
begin
  for Index := FRedoStack.Count - 1 downto 0 do
    if Find(FRedoStack[Index], ChangeSet) and (ChangeSet.State <> TAtlasChangeSetState.Applied) then
      Exit(ChangeSet.Id);
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
    Result := 'wiederhergestellt'
  else
    Result := 'zurückgenommen';
end;

function SameEncoding(const A, B: TAtlasTextFileContent): Boolean;
begin
  Result := (A.Encoding = B.Encoding) and (A.CodePage = B.CodePage);
end;

function TAtlasUndoJournal.Plan(const AChange: TAtlasFileChange; AIndex: Integer; ARedo: Boolean;
  out APlan: TPlan; out AProblem: TAtlasUndoProblem): Boolean;
var
  Current, Source, Target: TAtlasTextFileContent;
  Exists: Boolean;
  Kind: TAtlasFileChangeKind;
  Text: string;
begin
  APlan := Default(TPlan);
  APlan.Index := AIndex;
  APlan.Kind := TPlanKind.Nothing;
  AProblem := Default(TAtlasUndoProblem);
  AProblem.FileName := AChange.FileName;
  // Zurücknehmen: nachher → vorher; Wiederherstellen umgekehrt. Anlegen und Löschen tauschen dabei die Rollen.
  if ARedo then
  begin
    Source := AChange.Before;
    Target := AChange.After;
    Kind := AChange.Kind;
  end
  else
  begin
    Source := AChange.After;
    Target := AChange.Before;
    case AChange.Kind of
      TAtlasFileChangeKind.Created:
        Kind := TAtlasFileChangeKind.Deleted;
      TAtlasFileChangeKind.Deleted:
        Kind := TAtlasFileChangeKind.Created;
    else
      Kind := TAtlasFileChangeKind.Modified;
    end;
  end;
  try
    Exists := FTarget.Read(AChange.FileName, Current);
  except
    on E: Exception do
    begin
      AProblem.Kind := TAtlasUndoProblemKind.Failed;
      AProblem.Message := E.Message;
      Exit(False);
    end;
  end;
  case Kind of
    TAtlasFileChangeKind.Created:
      begin
        if Exists then
        begin
          // Schon genau so da (z. B. von Hand wiederhergestellt): nichts zu tun.
          if Current.Text = Target.Text then
            Exit(True);
          AProblem.Kind := TAtlasUndoProblemKind.Exists;
          Exit(False);
        end;
        APlan.Kind := TPlanKind.CreateFile;
        APlan.Content := Target;
      end;
    TAtlasFileChangeKind.Deleted:
      begin
        if not Exists then
          Exit(True);
        // Die ganze Datei ist die Änderung: Jede spätere Änderung ist ein Konflikt.
        if Current.Text <> Source.Text then
        begin
          AProblem.Kind := TAtlasUndoProblemKind.ChangedSince;
          Exit(False);
        end;
        APlan.Kind := TPlanKind.RemoveFile;
      end;
  else
    begin
      if not Exists then
      begin
        AProblem.Kind := TAtlasUndoProblemKind.Missing;
        Exit(False);
      end;
      if not TAtlasLinePatch.Rebase(Source.Text, Target.Text, Current.Text, Text) then
      begin
        AProblem.Kind := TAtlasUndoProblemKind.ChangedSince;
        Exit(False);
      end;
      APlan.Content := Current;
      APlan.Content.Text := Text;
      if not SameEncoding(Source, Target) and SameEncoding(Current, Source) then
      begin
        APlan.Content.Encoding := Target.Encoding;
        APlan.Content.CodePage := Target.CodePage;
      end;
      if (Text <> Current.Text) or not SameEncoding(APlan.Content, Current) then
        APlan.Kind := TPlanKind.Write;
    end;
  end;
  Result := True;
end;

function TAtlasUndoJournal.Run(AId: Integer; ARedo: Boolean): TAtlasUndoReport;
var
  SetPosition, Index: Integer;
  ChangeSet: TAtlasChangeSet;
  Plans: TArray<TPlan>;
  Planned: TPlan;
  Problem: TAtlasUndoProblem;
  Change: TAtlasFileChange;
  Mode: TAtlasNewFilesMode;
  Touched: Boolean;
begin
  Result := Default(TAtlasUndoReport);
  Result.SetId := AId;
  Result.Redo := ARedo;
  if not FOptions.Enabled then
  begin
    Result.Disabled := True;
    Exit;
  end;
  SetPosition := SetIndex(AId);
  if SetPosition < 0 then
  begin
    Result.NotFound := True;
    Exit;
  end;
  ChangeSet := FSets[SetPosition];
  Result.Action := ChangeSet.Action;
  // 1. Prüfen: alle betroffenen Dateien lesen, noch nichts ändern.
  Plans := nil;
  for Index := 0 to High(ChangeSet.Files) do
  begin
    Change := ChangeSet.Files[Index];
    // Zurücknehmen betrifft die noch angewendeten Dateien, Wiederherstellen die zurückgenommenen.
    if Change.Undone <> ARedo then
      Continue;
    if Plan(Change, Index, ARedo, Planned, Problem) then
      Plans := Plans + [Planned]
    else if Problem.Kind = TAtlasUndoProblemKind.Failed then
      Result.Errors := Result.Errors + [Problem]
    else
      Result.Conflicts := Result.Conflicts + [Problem];
  end;
  if (Length(Plans) = 0) and (Length(Result.Conflicts) = 0) and (Length(Result.Errors) = 0) then
  begin
    Result.NotFound := True;
    Exit;
  end;
  if ((Length(Result.Conflicts) > 0) or (Length(Result.Errors) > 0)) and
    (FOptions.OnConflict = TAtlasUndoConflictMode.Abort) then
  begin
    Result.Aborted := True;
    Log(Format('Atlas-Änderung #%d nicht %s: %d Konflikte, %d Fehler, abgebrochen',
      [AId, Verb(ARedo), Length(Result.Conflicts),
      Length(Result.Errors)]));
    Exit;
  end;
  // 2. Schreiben: jede Datei für sich; ein Fehler hält die anderen nicht auf.
  Touched := False;
  for Planned in Plans do
  begin
    Change := ChangeSet.Files[Planned.Index];
    try
      case Planned.Kind of
        TPlanKind.Write:
          FTarget.Write(Change.FileName, Planned.Content);
        TPlanKind.CreateFile:
          FTarget.CreateFile(Change.FileName, Change.Project, Planned.Content);
        TPlanKind.RemoveFile:
          begin
            Mode := FOptions.NewFiles;
            // Eine beim Wiederherstellen erneut gelöschte Datei bleibt nie liegen; ihr Inhalt steht im Satz.
            if ARedo and (Mode = TAtlasNewFilesMode.Keep) then
              Mode := TAtlasNewFilesMode.RecycleBin;
            FTarget.RemoveFile(Change.FileName, Change.Project, Mode);
          end;
      end;
    except
      on E: Exception do
      begin
        Problem := Default(TAtlasUndoProblem);
        Problem.FileName := Change.FileName;
        Problem.Kind := TAtlasUndoProblemKind.Failed;
        Problem.Message := E.Message;
        Result.Errors := Result.Errors + [Problem];
        Continue;
      end;
    end;
    ChangeSet.Files[Planned.Index].Undone := not ARedo;
    Result.Done := Result.Done + [Change.FileName];
    Touched := True;
  end;
  FSets[SetPosition] := ChangeSet;
  if Touched then
  begin
    FRedoStack.Remove(AId);
    if not ARedo or (ChangeSet.State <> TAtlasChangeSetState.Applied) then
      FRedoStack.Add(AId);
    if FStore <> nil then
      FStore.Save(ChangeSet);
  end;
  Log(Format('Atlas-Änderung #%d %s: %d Dateien, %d Konflikte, %d Fehler',
    [AId, Verb(ARedo), Length(Result.Done), Length(Result.Conflicts),
    Length(Result.Errors)]));
  if Touched then
    Changed;
end;

procedure TAtlasUndoJournal.Load;
var
  Loaded: TArray<TAtlasChangeSet>;
  ChangeSet: TAtlasChangeSet;
begin
  if FStore = nil then
    Exit;
  Loaded := FStore.Load;
  FSets.Clear;
  FRedoStack.Clear;
  for ChangeSet in Loaded do
  begin
    FSets.Add(ChangeSet);
    FNextId := Max(FNextId, ChangeSet.Id + 1);
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
    FStore.Clear;
  Changed;
end;

class function TAtlasUndoJournal.Diff(const AChange: TAtlasFileChange): TArray<string>;
begin
  Result := TAtlasTextDiff.Lines(AChange.Before.Text, AChange.After.Text);
end;

end.
