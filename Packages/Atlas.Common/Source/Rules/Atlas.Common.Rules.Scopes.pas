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

procedure Collect(ANode: TSyntaxNode; const AOuter: string; var ARoutines, ASections: TArray<TFindingScope>);
var
  Index: Integer;
  Child: TSyntaxNode;
  Name, Section: string;
begin
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Child := ANode[Index];
    Name := AOuter;
    if (Child.Kind = TSyntaxKind.RoutineDecl) and (Child.Name <> '') and HasBody(Child) then
    begin
      if AOuter = '' then
        Name := Child.Name
      else
        Name := AOuter + '.' + Child.Name;
      ARoutines := ARoutines + [Scope(Name, Child)];
    end
    else if AOuter = '' then
    begin
      Section := SectionName(Child.Kind);
      if Section <> '' then
        ASections := ASections + [Scope(Section, Child)];
    end;
    // Routinen stehen nie in Anweisungen und Ausdrücken; dort nicht absteigen, sonst läuft der Stapel
    // bei sehr tiefen Ausdrücken über (#1094).
    if not (Child.Kind in [TSyntaxKind.Block .. TSyntaxKind.IfExpr]) then
      Collect(Child, Name, ARoutines, ASections);
  end;
end;

{ TFindingScopes }

class function TFindingScopes.FromTree(ATree: TSyntaxTree): TFindingScopes;
var
  Section: string;
begin
  Result.FRoutines := nil;
  Result.FSections := nil;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Section := SectionName(ATree.Root.Kind);
  if Section <> '' then
    Result.FSections := [Scope(Section, ATree.Root)];
  Collect(ATree.Root, '', Result.FRoutines, Result.FSections);
end;

class function TFindingScopes.FromText(const AText: string): TFindingScopes;
var
  Tree: TSyntaxTree;
begin
  Tree := TSyntaxTreeCache.Parse(AText);
  try
    Result := FromTree(Tree);
  finally
    Tree.Free;
  end;
end;

function TFindingScopes.At(ALine: Integer): string;
var
  Index: Integer;
begin
  // Die letzte passende Routine ist die innerste: innere stehen hinter ihrer äußeren.
  for Index := High(FRoutines) downto 0 do
    if (FRoutines[Index].FirstLine <= ALine) and (ALine <= FRoutines[Index].LastLine) then
      Exit(FRoutines[Index].Name);
  for Index := High(FSections) downto 0 do
    if (FSections[Index].FirstLine <= ALine) and (ALine <= FSections[Index].LastLine) then
      Exit(FSections[Index].Name);
  // Hinter dem Ende des Baums (z. B. Text nach "end."): die Datei.
  if Length(FSections) > 0 then
    Result := FSections[0].Name
  else
    Result := '';
end;

function TFindingScopes.HeaderLine(ALine: Integer): Integer;
var
  Index: Integer;
begin
  for Index := High(FRoutines) downto 0 do
    if (FRoutines[Index].FirstLine <= ALine) and (ALine <= FRoutines[Index].LastLine) then
      Exit(FRoutines[Index].FirstLine);
  Result := -1;
end;

function TFindingScopes.HasRoutine(const AName: string): Boolean;
var
  Item: TFindingScope;
begin
  for Item in FRoutines do
    if SameText(Item.Name, AName) then
      Exit(True);
  Result := False;
end;

function TFindingScopes.RoutineCount: Integer;
begin
  Result := Length(FRoutines);
end;

end.
