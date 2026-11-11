unit Atlas.Common.Rules.Scopes;

// Umgebende Routine eines Regeltreffers (#97), Teil des Baseline-Schlüssels:
// - In einer Routine mit Rumpf der voll qualifizierte Name aus dem Kopf,
//   z. B. "TFoo.Bar"; lokale Routinen hängen ihren Namen mit Punkt an
//   ("TFoo.Bar.Lokal"). Kopf, lokale Deklarationen und Rumpf gehören dazu.
// - Außerhalb einer Routine der Unit-Abschnitt: "interface",
//   "implementation", "initialization", "finalization"; vor dem ersten
//   Abschnitt und im Hauptblock von Programmen, Bibliotheken und Packages
//   die Art der Datei ("unit", "program", "library", "package").
// Forward- und external-Deklarationen haben keinen Rumpf und zählen nicht als
// Routine. Zeilen beginnen bei 0 wie im LSP.

interface

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Benannter Zeilenbereich (Routine oder Abschnitt).</summary>
  TFindingScope = record
    Name: string;
    FirstLine: Integer;
    LastLine: Integer;
  end;

  /// <summary>Routinen und Abschnitte einer Datei; unveränderlich, ohne Verweis auf den Syntaxbaum.</summary>
  TFindingScopes = record
  private
    /// <summary>In Baumreihenfolge: äußere vor inneren Routinen.</summary>
    FRoutines: TArray<TFindingScope>;
    /// <summary>Datei zuerst, dann die Abschnitte.</summary>
    FSections: TArray<TFindingScope>;
  public
    /// <summary>Bereiche aus ATree; nil ergibt eine leere Menge.</summary>
    class function FromTree(ATree: TSyntaxTree): TFindingScopes; static;
    /// <summary>Parst AText und liest die Bereiche.</summary>
    class function FromText(const AText: string): TFindingScopes; static;
    /// <summary>Name der Routine bzw. des Abschnitts an Zeile ALine; '' ohne Bereich.</summary>
    function At(ALine: Integer): string;
    /// <summary>True, wenn die Datei eine Routine mit Rumpf namens AName enthält (ohne Groß- und Kleinschreibung).
    /// </summary>
    function HasRoutine(const AName: string): Boolean;
    /// <summary>Erste Zeile (Kopf) der innersten Routine an ALine; -1 außerhalb einer Routine.</summary>
    function HeaderLine(ALine: Integer): Integer;
    /// <summary>Anzahl der Routinen mit Rumpf.</summary>
    function RoutineCount: Integer;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Pascal.TreeCache;

function HasBody(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.FindChild(TSyntaxKind.Block) <> nil) or (ANode.FindChild(TSyntaxKind.AsmBlock) <> nil);
end;

function Scope(const AName: string; ANode: TSyntaxNode): TFindingScope;
begin
  Result.Name := AName;
  Result.FirstLine := ANode.StartPos.Line;
  Result.LastLine := ANode.EndPos.Line;
end;

function SectionName(AKind: TSyntaxKind): string;
begin
  case AKind of
    TSyntaxKind.InterfaceSection:
      Result := 'interface';
    TSyntaxKind.ImplementationSection:
      Result := 'implementation';
    TSyntaxKind.InitializationSection:
      Result := 'initialization';
    TSyntaxKind.FinalizationSection:
      Result := 'finalization';
    TSyntaxKind.UnitFile:
      Result := 'unit';
    TSyntaxKind.ProgramFile:
      Result := 'program';
    TSyntaxKind.LibraryFile:
      Result := 'library';
    TSyntaxKind.PackageFile:
      Result := 'package';
  else
    Result := '';
  end;
end;

/// <summary>Trägt ANode als Routine (Name mit AOuter) oder als Abschnitt der obersten Ebene ein; liefert den
/// Namen der Routine, die seine Kinder umschließt.</summary>
function AddScope(ANode: TSyntaxNode; const AOuter: string; var ARoutines, ASections: TArray<TFindingScope>):
  string;
begin
  Result := AOuter;
  if (ANode.Kind = TSyntaxKind.RoutineDecl) and (ANode.Name <> '') and HasBody(ANode) then
  begin
    if AOuter = '' then
    begin
      Result := ANode.Name;
    end
    else
    begin
      Result := AOuter + '.' + ANode.Name;
    end;
    ARoutines := ARoutines + [Scope(Result, ANode)];
  end
  else if (AOuter = '') and (SectionName(ANode.Kind) <> '') then
  begin
    ASections := ASections + [Scope(SectionName(ANode.Kind), ANode)];
  end;
end;

// Iterativ (tiefe Bäume sprengen den Stapel nicht): neben jedem Knoten liegt der Name der umschließenden Routine auf dem Stapel.
procedure Collect(ARoot: TSyntaxNode; var ARoutines, ASections: TArray<TFindingScope>);
var
  mPending: TStack<TSyntaxNode>;
  mPendingOuter: TStack<string>;
  mIndex: Integer;
  mChild: TSyntaxNode;
  mName: string;
begin
  mPending := TStack<TSyntaxNode>.Create;
  mPendingOuter := TStack<string>.Create;
  try
    for mIndex := ARoot.ChildCount - 1 downto 0 do
    begin
      mPending.Push(ARoot[mIndex]);
      mPendingOuter.Push('');
    end;
    while mPending.Count > 0 do
    begin
      mChild := mPending.Pop;
      mName := AddScope(mChild, mPendingOuter.Pop, ARoutines, ASections);
      // Routinen stehen nie in Anweisungen und Ausdrücken; dort nicht absteigen (#1094).
      if not (mChild.Kind in [TSyntaxKind.Block .. TSyntaxKind.IfExpr]) then
      begin
        for mIndex := mChild.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mChild[mIndex]);
          mPendingOuter.Push(mName);
        end;
      end;
    end;
  finally
    mPendingOuter.Free;
    mPending.Free;
  end;
end;

{ TFindingScopes }

class function TFindingScopes.FromTree(ATree: TSyntaxTree): TFindingScopes;
var
  mSection: string;
begin
  Result.FRoutines := nil;
  Result.FSections := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mSection := SectionName(ATree.Root.Kind);
  if mSection <> '' then
  begin
    Result.FSections := [Scope(mSection, ATree.Root)];
  end;
  Collect(ATree.Root, Result.FRoutines, Result.FSections);
end;

class function TFindingScopes.FromText(const AText: string): TFindingScopes;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    Result := FromTree(mTree);
  finally
    mTree.Free;
  end;
end;

function TFindingScopes.At(ALine: Integer): string;
var
  mIndex: Integer;
begin
  // Die letzte passende Routine ist die innerste: innere stehen hinter ihrer äußeren.
  for mIndex := High(FRoutines) downto 0 do
  begin
    if (FRoutines[mIndex].FirstLine <= ALine) and (ALine <= FRoutines[mIndex].LastLine) then
    begin
      Exit(FRoutines[mIndex].Name);
    end;
  end;
  for mIndex := High(FSections) downto 0 do
  begin
    if (FSections[mIndex].FirstLine <= ALine) and (ALine <= FSections[mIndex].LastLine) then
    begin
      Exit(FSections[mIndex].Name);
    end;
  end;
  // Hinter dem Ende des Baums (z. B. Text nach "end."): die Datei.
  if Length(FSections) > 0 then
  begin
    Result := FSections[0].Name;
  end
  else
  begin
    Result := '';
  end;
end;

function TFindingScopes.HeaderLine(ALine: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := High(FRoutines) downto 0 do
  begin
    if (FRoutines[mIndex].FirstLine <= ALine) and (ALine <= FRoutines[mIndex].LastLine) then
    begin
      Exit(FRoutines[mIndex].FirstLine);
    end;
  end;
  Result := -1;
end;

function TFindingScopes.HasRoutine(const AName: string): Boolean;
var
  mItem: TFindingScope;
begin
  for mItem in FRoutines do
  begin
    if SameText(mItem.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TFindingScopes.RoutineCount: Integer;
begin
  Result := Length(FRoutines);
end;

end.
