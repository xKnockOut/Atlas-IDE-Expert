unit Atlas.Core.Debug.ParallelStacks;

// Parallele Aufrufstapel (#837), ohne VCL und Open Tools API: die Aufrufstapel aller Threads zusammengeführt als
// Baum, von unten (Thread-Start) nach oben (aktueller Rahmen).
//   - Gleiche Rahmen (gleiche Routine an gleicher Stelle: Routine, Datei, Zeile) stehen einmal da, mit den Threads,
//     die durch sie laufen; der Baum verzweigt dort, wo sich die Stapel trennen.
//   - Wartend ist ein Thread, wenn über seinem ersten eigenen Rahmen (ohne eigenen Rahmen: im ganzen Stapel) eine
//     der Warte-Routinen steht (debug.parallelStacks.waitRoutines, Vergleich wie TAtlasDebugWaits.Matches).
//   - Filter „Nur eigener Code“ lässt Rahmen außerhalb des eigenen Codes weg (#578), „Wartend“ nimmt nur wartende
//     Threads auf.
// Threads mit unlesbarem Stapel fehlen im Baum.

interface

uses
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.Threads;

type
  TAtlasDebugStackFilter = record
    OwnCodeOnly: Boolean;
    WaitingOnly: Boolean;
  end;

  TAtlasDebugStackNode = record
    /// <summary>Rahmen des ersten Threads, der durch den Knoten läuft.</summary>
    Frame: TAtlasDebugFrame;
    /// <summary>Indizes in die Stapelliste.</summary>
    Threads: TArray<Integer>;
    /// <summary>Index des Elternknotens (näher am Thread-Start); -1 bei einer Wurzel.</summary>
    Parent: Integer;
    Children: TArray<Integer>;
    /// <summary>So viele der Threads warten.</summary>
    Waiting: Integer;
    /// <summary>Läuft der aktuelle Thread durch den Knoten?</summary>
    Current: Boolean;
    /// <summary>Alle Threads des Knotens warten.</summary>
    function AllWaiting: Boolean;
  end;

  TAtlasDebugStackTree = record
    Nodes: TArray<TAtlasDebugStackNode>;
    Roots: TArray<Integer>;
    /// <summary>Wartet der Thread AIndex der Stapelliste?</summary>
    Waiting: TArray<Boolean>;
    /// <summary>Baum aus AStacks; ACurrent: Index des aktuellen Threads (-1 ohne); ARoutines: Warte-Routinen.</summary>
    class function Build(const AStacks: TAtlasDebugThreadStacks; ACurrent: Integer;
      const ARoutines: TArray<string>; const AFilter: TAtlasDebugStackFilter): TAtlasDebugStackTree; static;
    /// <summary>Wartet AStack an einer der Routinen ARoutines (siehe Kopf)?</summary>
    class function IsWaiting(const AStack: TAtlasDebugThreadStack; const ARoutines: TArray<string>): Boolean;
      static;
    /// <summary>Routinen aus dem Text der Einstellung (durch ; getrennt, Leerraum egal); leer = Vorgabe.</summary>
    class function ParseRoutines(const AText: string): TArray<string>; static;
    /// <summary>Vorgabe der Einstellung: die Warte-Routinen aus TAtlasDebugWaits ohne die Nachrichtenschleife.
    /// </summary>
    class function DefaultRoutinesText: string; static;
  end;

implementation

uses
  System.SysUtils;

const
  cIdlePrefix = 'Idle=';
  cSeparator = ';';

function SameFrame(const A, B: TAtlasDebugFrame): Boolean;
begin
  Result := SameText(A.Routine, B.Routine) and SameText(A.FileName, B.FileName) and (A.Line = B.Line);
end;

/// <summary>Rahmen von AStack von unten nach oben, gefiltert nach AOwnCodeOnly.</summary>
function BottomUp(const AStack: TAtlasDebugThreadStack; AOwnCodeOnly: Boolean): TAtlasDebugFrames;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := High(AStack.Frames) downto 0 do
  begin
    if AOwnCodeOnly and not AStack.Frames[mIndex].Own then
    begin
      Continue;
    end;
    Result := Result + [AStack.Frames[mIndex]];
  end;
end;

{ TAtlasDebugStackNode }

function TAtlasDebugStackNode.AllWaiting: Boolean;
begin
  Result := (Threads <> nil) and (Waiting = Length(Threads));
end;

{ TAtlasDebugStackTree }

class function TAtlasDebugStackTree.IsWaiting(const AStack: TAtlasDebugThreadStack;
  const ARoutines: TArray<string>): Boolean;
var
  mIndex, mStop: Integer;
  mRoutine, mPattern: string;
begin
  mStop := AStack.FirstOwn;
  if mStop < 0 then
  begin
    mStop := Length(AStack.Frames);
  end;
  for mIndex := 0 to mStop - 1 do
  begin
    mRoutine := AStack.Frames[mIndex].Routine;
    for mPattern in ARoutines do
    begin
      if TAtlasDebugWaits.Matches(mRoutine, mPattern) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

class function TAtlasDebugStackTree.ParseRoutines(const AText: string): TArray<string>;
var
  mPart: string;
begin
  Result := nil;
  for mPart in AText.Split([cSeparator]) do
  begin
    if Trim(mPart) <> '' then
    begin
      Result := Result + [Trim(mPart)];
    end;
  end;
  if Result = nil then
  begin
    Result := DefaultRoutinesText.Split([cSeparator]);
  end;
end;

class function TAtlasDebugStackTree.DefaultRoutinesText: string;
var
  mEntry: string;
begin
  Result := '';
  for mEntry in TAtlasDebugWaits.DefaultRoutines do
  begin
    if mEntry.StartsWith(cIdlePrefix) then
    begin
      Continue;
    end;
    if Result <> '' then
    begin
      Result := Result + cSeparator;
    end;
    Result := Result + Copy(mEntry, Pos('=', mEntry) + 1, MaxInt);
  end;
end;

/// <summary>Kind von AParent (-1: Wurzel) mit dem Rahmen AFrame; legt es bei Bedarf an.</summary>
function ChildFor(var ATree: TAtlasDebugStackTree; AParent: Integer; const AFrame: TAtlasDebugFrame): Integer;
var
  mSiblings: TArray<Integer>;
  mIndex: Integer;
  mNode: TAtlasDebugStackNode;
begin
  if AParent < 0 then
  begin
    mSiblings := ATree.Roots;
  end
  else
  begin
    mSiblings := ATree.Nodes[AParent].Children;
  end;
  for mIndex in mSiblings do
  begin
    if SameFrame(ATree.Nodes[mIndex].Frame, AFrame) then
    begin
      Exit(mIndex);
    end;
  end;
  mNode := Default(TAtlasDebugStackNode);
  mNode.Frame := AFrame;
  mNode.Parent := AParent;
  ATree.Nodes := ATree.Nodes + [mNode];
  Result := High(ATree.Nodes);
  if AParent < 0 then
  begin
    ATree.Roots := ATree.Roots + [Result];
  end
  else
  begin
    ATree.Nodes[AParent].Children := ATree.Nodes[AParent].Children + [Result];
  end;
end;

class function TAtlasDebugStackTree.Build(const AStacks: TAtlasDebugThreadStacks; ACurrent: Integer;
  const ARoutines: TArray<string>; const AFilter: TAtlasDebugStackFilter): TAtlasDebugStackTree;
var
  mThread, mNode: Integer;
  mFrame: TAtlasDebugFrame;
begin
  Result := Default(TAtlasDebugStackTree);
  SetLength(Result.Waiting, Length(AStacks));
  for mThread := 0 to High(AStacks) do
  begin
    Result.Waiting[mThread] := AStacks[mThread].Readable and IsWaiting(AStacks[mThread], ARoutines);
    if (not AStacks[mThread].Readable) or (AFilter.WaitingOnly and not Result.Waiting[mThread]) then
    begin
      Continue;
    end;
    mNode := -1;
    for mFrame in BottomUp(AStacks[mThread], AFilter.OwnCodeOnly) do
    begin
      mNode := ChildFor(Result, mNode, mFrame);
      Result.Nodes[mNode].Threads := Result.Nodes[mNode].Threads + [mThread];
      if Result.Waiting[mThread] then
      begin
        Inc(Result.Nodes[mNode].Waiting);
      end;
      if mThread = ACurrent then
      begin
        Result.Nodes[mNode].Current := True;
      end;
    end;
  end;
end;

end.
