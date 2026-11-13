unit Atlas.Core.Debug.ThreadMarks;

// Threads im Quelltext (#852), ohne VCL und Open Tools API:
//   - TAtlasDebugThreadSet: Menge von Thread-Kennungen für die Sitzung, je für markierte und eingefrorene Threads.
//     Die Einträge folgen der Kennung, nicht der Stelle in der Liste der IDE.
//   - TAtlasDebugThreadMarks: je Zeile im Quelltext die Threads, deren oberster eigener Rahmen dort steht (ohne den
//     aktuellen Thread, dessen Zeile die IDE selbst zeigt). Markierte Threads stehen in jeder Liste oben, sonst gilt
//     die Reihenfolge der IDE.
// Dateien vergleicht Atlas ohne Groß-/Kleinschreibung und mit \ und / gleich.

interface

uses
  Atlas.Core.Debug.Threads;

type
  TAtlasDebugThreadSet = record
  private
    FIds: TArray<Cardinal>;
  public
    function Contains(AId: Cardinal): Boolean;
    procedure Add(AId: Cardinal);
    procedure Remove(AId: Cardinal);
    /// <summary>Hinzufügen oder entfernen; True, wenn AId danach enthalten ist.</summary>
    function Toggle(AId: Cardinal): Boolean;
    procedure Clear;
    function Count: Integer;
    function Ids: TArray<Cardinal>;
  end;

  TAtlasDebugThreadMark = record
    FileName: string;
    /// <summary>1-basiert.</summary>
    Line: Integer;
    /// <summary>Indizes in die Stapelliste, markierte zuerst.</summary>
    Threads: TArray<Integer>;
  end;

  TAtlasDebugThreadMarks = record
  public
    Marks: TArray<TAtlasDebugThreadMark>;
    /// <summary>Zeilen der Threads aus AStacks; ACurrent: Index des aktuellen Threads (-1 ohne).</summary>
    class function Build(const AStacks: TAtlasDebugThreadStacks; ACurrent: Integer;
      const AFlagged: TAtlasDebugThreadSet): TAtlasDebugThreadMarks; static;
    /// <summary>Indizes AThreads, markierte zuerst, sonst in der gegebenen Reihenfolge.</summary>
    class function Ordered(const AStacks: TAtlasDebugThreadStacks; const AThreads: TArray<Integer>;
      const AFlagged: TAtlasDebugThreadSet): TArray<Integer>; static;
    /// <summary>Gleiche Datei (siehe Kopf)?</summary>
    class function SameFile(const A, B: string): Boolean; static;
    /// <summary>Index der Markierung an ALine (1-basiert) in AFileName; -1 ohne.</summary>
    function IndexAt(const AFileName: string; ALine: Integer): Integer;
    function HasFile(const AFileName: string): Boolean;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasDebugThreadSet }

function TAtlasDebugThreadSet.Contains(AId: Cardinal): Boolean;
var
  mId: Cardinal;
begin
  for mId in FIds do
  begin
    if mId = AId then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TAtlasDebugThreadSet.Add(AId: Cardinal);
begin
  if not Contains(AId) then
  begin
    FIds := FIds + [AId];
  end;
end;

procedure TAtlasDebugThreadSet.Remove(AId: Cardinal);
var
  mIndex: Integer;
begin
  for mIndex := High(FIds) downto 0 do
  begin
    if FIds[mIndex] = AId then
    begin
      Delete(FIds, mIndex, 1);
    end;
  end;
end;

function TAtlasDebugThreadSet.Toggle(AId: Cardinal): Boolean;
begin
  Result := not Contains(AId);
  if Result then
  begin
    Add(AId);
  end
  else
  begin
    Remove(AId);
  end;
end;

procedure TAtlasDebugThreadSet.Clear;
begin
  FIds := nil;
end;

function TAtlasDebugThreadSet.Count: Integer;
begin
  Result := Length(FIds);
end;

function TAtlasDebugThreadSet.Ids: TArray<Cardinal>;
begin
  Result := Copy(FIds);
end;

{ TAtlasDebugThreadMarks }

class function TAtlasDebugThreadMarks.SameFile(const A, B: string): Boolean;
begin
  Result := SameText(A.Replace('/', '\'), B.Replace('/', '\'));
end;

class function TAtlasDebugThreadMarks.Ordered(const AStacks: TAtlasDebugThreadStacks;
  const AThreads: TArray<Integer>; const AFlagged: TAtlasDebugThreadSet): TArray<Integer>;
var
  mFlagged, mOthers: TArray<Integer>;
  mThread: Integer;
begin
  mFlagged := nil;
  mOthers := nil;
  for mThread in AThreads do
  begin
    if (mThread >= 0) and (mThread <= High(AStacks)) and AFlagged.Contains(AStacks[mThread].ThreadId) then
    begin
      mFlagged := mFlagged + [mThread];
    end
    else
    begin
      mOthers := mOthers + [mThread];
    end;
  end;
  Result := mFlagged + mOthers;
end;

function TAtlasDebugThreadMarks.IndexAt(const AFileName: string; ALine: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Marks) do
  begin
    if (Marks[mIndex].Line = ALine) and SameFile(Marks[mIndex].FileName, AFileName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasDebugThreadMarks.HasFile(const AFileName: string): Boolean;
var
  mMark: TAtlasDebugThreadMark;
begin
  for mMark in Marks do
  begin
    if SameFile(mMark.FileName, AFileName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasDebugThreadMarks.Build(const AStacks: TAtlasDebugThreadStacks; ACurrent: Integer;
  const AFlagged: TAtlasDebugThreadSet): TAtlasDebugThreadMarks;
var
  mThread, mOwn, mMark: Integer;
  mNew: TAtlasDebugThreadMark;
begin
  Result := Default(TAtlasDebugThreadMarks);
  for mThread := 0 to High(AStacks) do
  begin
    if (mThread = ACurrent) or not AStacks[mThread].Readable then
    begin
      Continue;
    end;
    mOwn := AStacks[mThread].FirstOwn;
    if mOwn < 0 then
    begin
      Continue;
    end;
    mMark := Result.IndexAt(AStacks[mThread].Frames[mOwn].FileName, AStacks[mThread].Frames[mOwn].Line);
    if mMark < 0 then
    begin
      mNew := Default(TAtlasDebugThreadMark);
      mNew.FileName := AStacks[mThread].Frames[mOwn].FileName;
      mNew.Line := AStacks[mThread].Frames[mOwn].Line;
      Result.Marks := Result.Marks + [mNew];
      mMark := High(Result.Marks);
    end;
    Result.Marks[mMark].Threads := Result.Marks[mMark].Threads + [mThread];
  end;
  for mMark := 0 to High(Result.Marks) do
  begin
    Result.Marks[mMark].Threads := Ordered(AStacks, Result.Marks[mMark].Threads, AFlagged);
  end;
end;

end.
