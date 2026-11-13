unit Atlas.UI.Debug.ParallelStacks;

// Parallele Aufrufstapel (#837), Texte ohne VCL: Knoten „TWorker.Execute (Unit2.pas:30) · 10 Threads · wartend“,
// Zeile mit den Threads eines Knotens und die Statuszeile des Fensters.

interface

uses
  Atlas.Core.Debug.Threads,
  Atlas.Core.Debug.ParallelStacks;

type
  TAtlasParallelStacksTexts = class
  public
    /// <summary>Text eines Knotens: Routine, Ort, Zahl der Threads, „wartend“, wenn alle warten.</summary>
    class function NodeText(const ANode: TAtlasDebugStackNode): string; static;
    /// <summary>„Threads: 7 „Worker“, 8, 9“ für den gewählten Knoten.</summary>
    class function ThreadsText(const ANode: TAtlasDebugStackNode; const AStacks: TAtlasDebugThreadStacks): string;
      static;
    /// <summary>„12 Threads, 8 wartend“.</summary>
    class function StatusText(const ATree: TAtlasDebugStackTree): string; static;
    /// <summary>Thread für die Auswahlliste: „7 „Worker““ bzw. „8“.</summary>
    class function ThreadText(const AStack: TAtlasDebugThreadStack): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Debug.Strings;

{ TAtlasParallelStacksTexts }

class function TAtlasParallelStacksTexts.NodeText(const ANode: TAtlasDebugStackNode): string;
begin
  Result := ANode.Frame.Routine;
  if ANode.Frame.HasSource then
  begin
    Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugWaitsPlace,
      [Result, ExtractFileName(ANode.Frame.FileName), ANode.Frame.Line]);
  end;
  if Length(ANode.Threads) = 1 then
  begin
    Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.ParallelStacksNodeOne, [Result]);
  end
  else
  begin
    Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.ParallelStacksNode, [Result, Length(ANode.Threads)]);
  end;
  if ANode.AllWaiting then
  begin
    Result := Result + TAtlasDebugStrings.Text(TAtlasDebugTextId.ParallelStacksNodeWaiting);
  end;
end;

class function TAtlasParallelStacksTexts.ThreadText(const AStack: TAtlasDebugThreadStack): string;
begin
  Result := IntToStr(AStack.ThreadId);
  if AStack.Name <> '' then
  begin
    Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugWaitsThreadName, [Result, AStack.Name]);
  end;
end;

class function TAtlasParallelStacksTexts.ThreadsText(const ANode: TAtlasDebugStackNode;
  const AStacks: TAtlasDebugThreadStacks): string;
var
  mIndex: Integer;
  mNames: TArray<string>;
begin
  SetLength(mNames, Length(ANode.Threads));
  for mIndex := 0 to High(ANode.Threads) do
  begin
    mNames[mIndex] := ThreadText(AStacks[ANode.Threads[mIndex]]);
  end;
  Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.ParallelStacksThreads, [string.Join(', ', mNames)]);
end;

class function TAtlasParallelStacksTexts.StatusText(const ATree: TAtlasDebugStackTree): string;
var
  mWaiting: Boolean;
  mCount: Integer;
begin
  mCount := 0;
  for mWaiting in ATree.Waiting do
  begin
    if mWaiting then
    begin
      Inc(mCount);
    end;
  end;
  Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.ParallelStacksStatus, [Length(ATree.Waiting), mCount]);
end;

end.
