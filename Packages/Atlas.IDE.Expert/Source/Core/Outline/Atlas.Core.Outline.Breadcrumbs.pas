unit Atlas.Core.Outline.Breadcrumbs;

// Brotkrumenleiste (#590), Kern ohne VCL und OTA:
// - Path berechnet aus der Gliederung (TAtlasOutline.FromJson) und dem Text
//   den Pfad am Caret: Unit › Typ › (verschachtelter Typ) › Methode › lokale
//   Prozedur. Im Rumpf einer Methode stehen die Typen ihrer Deklaration davor;
//   im interface endet der Pfad beim Typ bzw. Member. Im Abschnitt uses steht
//   „uses“, in initialization/finalization dieser Abschnitt (aus dem Text,
//   weil documentSymbol sie nicht kennt).
// - Jedes Glied kennt seine Geschwister für das Sprungmenü in
//   Quelltextreihenfolge: Mitglieder des Typs (bei Methoden nur Methoden),
//   lokale Routinen desselben Rumpfs bzw. auf Unit-Ebene alle Typen, alle
//   Routinen oder alle Konstanten und Variablen. Das Unit-Glied bietet alle
//   Elemente der Unit-Ebene an (Ersatz für „Typ suchen“/„Methode suchen“ der
//   IDE-Navigationsleiste).
// - Jedes Glied kennt außerdem seine Kinder für das Menü hinter „›“ (wie die
//   Adressleiste im Explorer): Mitglieder eines Typs, lokale Routinen einer
//   Methode, beim Unit-Glied die Elemente der Unit-Ebene.
// - Target wählt das Sprungziel (Implementierung oder Deklaration), Filter
//   die Wortgrenzen-Suche des Menüs.

interface

uses
  System.SysUtils,
  Atlas.Core.Style.Palette,
  Atlas.Core.Completion.Presentation,
  Atlas.Core.Outline.Model;

type
{$SCOPEDENUMS ON}
  TAtlasCodeSection = (None, InterfacePart, ImplementationPart, UsesClause, Initialization_, Finalization_);
{$SCOPEDENUMS OFF}

  TAtlasCrumb = record
    Text: string;
    Badge: TAtlasBadge;
    /// <summary>Knoten der Gliederung (bei Methoden die Deklaration); -1 bei Unit, Abschnitt und Besitzern,
    /// die es in der Unit nicht gibt.</summary>
    Node: Integer;
    /// <summary>Geschwister für das Sprungmenü in Quelltextreihenfolge; leer = kein Menü.</summary>
    Siblings: TArray<Integer>;
    /// <summary>Index von Node in Siblings; -1, wenn nicht enthalten.</summary>
    Current: Integer;
    /// <summary>Kinder für das Menü hinter dem Glied in Quelltextreihenfolge; leer = kein Menü.</summary>
    Children: TArray<Integer>;
  end;

  TAtlasCrumbs = TArray<TAtlasCrumb>;

  TAtlasBreadcrumbs = class
  public
    /// <summary>Abschnitt der Zeile ALine (0-basiert): Schlüsselwörter am Zeilenanfang (Spalte 1), uses bis zum
    /// abschließenden Semikolon; Kommentare und Strings zählen nicht.</summary>
    class function SectionAt(const ALines: TArray<string>; ALine: Integer): TAtlasCodeSection; static;
    /// <summary>Pfad am Caret (0-basiert). AUnitName steht vorn, wenn AShowUnit.</summary>
    class function Path(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ALine,
      ACharacter: Integer; const AUnitName: string; AShowUnit: Boolean): TAtlasCrumbs; static;
    /// <summary>Badge eines Knotens; Routinen nach dem ersten Wort ihrer Kopfzeile (procedure/function).</summary>
    class function BadgeOf(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
      ANode: Integer): TAtlasBadge; static;
    /// <summary>Elemente der Unit-Ebene (Typen, Routinen, Konstanten, Variablen) in Quelltextreihenfolge; Rümpfe
    /// mit Deklaration nur einmal.</summary>
    class function UnitMembers(const ANodes: TAtlasOutlineNodes): TArray<Integer>; static;
    /// <summary>Alle Methoden und Routinen der Unit in Quelltextreihenfolge, ohne lokale Routinen; Rümpfe mit
    /// Deklaration nur einmal (als Deklaration). Für „Methode suchen“ der Editorleiste (#1101).</summary>
    class function Routines(const ANodes: TAtlasOutlineNodes): TArray<Integer>; static;
    /// <summary>Name mit Besitzer: Methoden einer Klasse als „TFoo.Bar“, sonst der Name.</summary>
    class function QualifiedName(const ANodes: TAtlasOutlineNodes; ANode: Integer): string; static;
    /// <summary>Kinder von ANode: Mitglieder eines Typs bzw. lokale Routinen im Rumpf einer Routine.</summary>
    class function Children(const ANodes: TAtlasOutlineNodes; ANode: Integer): TArray<Integer>; static;
    /// <summary>Name ohne Besitzer: "TFoo.Bar" → "Bar".</summary>
    class function ShortName(const AName: string): string; static;
    /// <summary>Sprungziel: mit AImplementation der Rumpf (ohne Rumpf die Deklaration), sonst die
    /// Deklaration (für einen Rumpf dessen Deklaration).</summary>
    class function Target(const ANodes: TAtlasOutlineNodes; ANode: Integer; AImplementation: Boolean): Integer;
      static;
    /// <summary>Geschwister, deren Name an einer Wortgrenze mit APattern beginnt (ohne Groß-/Kleinschreibung),
    /// in der Reihenfolge von ASiblings; leeres Muster = alle.</summary>
    class function Filter(const ANodes: TAtlasOutlineNodes; const ASiblings: TArray<Integer>;
      const APattern: string): TArray<Integer>; static;
    /// <summary>APattern beginnt an einer Wortgrenze von AName (Anfang, Großbuchstabe nach Kleinbuchstabe,
    /// nach Unterstrich oder Ziffernwechsel) oder passt auf die Wortanfänge (wie die Vervollständigung).</summary>
    class function MatchesAtWordStart(const APattern, AName: string): Boolean; static;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Completion.Matching;

const
  KindNamespace = 3;

function MakeBadge(AKind: TAtlasBadgeKind; const ACode: string): TAtlasBadge;
begin
  Result.Kind := AKind;
  Result.Code := ACode;
end;

/// <summary>Wort am Anfang der Zeile (Spalte 1), klein; leer, wenn die Zeile mit Leerraum oder einem anderen
/// Zeichen beginnt.</summary>
function LeadingWord(const ALine: string): string;
var
  Index: Integer;
begin
  Index := 1;
  while (Index <= Length(ALine)) and CharInSet(ALine[Index], ['a'..'z', 'A'..'Z', '_']) do
    Inc(Index);
  Result := LowerCase(Copy(ALine, 1, Index - 1));
end;

class function TAtlasBreadcrumbs.SectionAt(const ALines: TArray<string>; ALine: Integer): TAtlasCodeSection;
var
  Index, Position: Integer;
  Line, Word_: string;
  Section, BeforeUses: TAtlasCodeSection;
  InUses: Boolean;
  Comment: Char;
  InString: Boolean;
begin
  Section := TAtlasCodeSection.None;
  BeforeUses := TAtlasCodeSection.None;
  InUses := False;
  // Offener Kommentar über Zeilen: '{' oder '(' für (* *); #0 = keiner.
  Comment := #0;
  for Index := 0 to Min(ALine, High(ALines)) do
  begin
    Line := ALines[Index];
    if (Comment = #0) and not InUses then
    begin
      Word_ := LeadingWord(Line);
      if Word_ = 'interface' then
        Section := TAtlasCodeSection.InterfacePart
      else if Word_ = 'implementation' then
        Section := TAtlasCodeSection.ImplementationPart
      else if Word_ = 'initialization' then
        Section := TAtlasCodeSection.Initialization_
      else if Word_ = 'finalization' then
        Section := TAtlasCodeSection.Finalization_
      else if (Word_ = 'end') and (Copy(Line, 4, 1) = '.') then
        Section := TAtlasCodeSection.None
      else if Word_ = 'uses' then
      begin
        BeforeUses := Section;
        Section := TAtlasCodeSection.UsesClause;
        InUses := True;
      end;
    end;
    // Kommentare über Zeilen und das Semikolon am Ende von uses.
    InString := False;
    Position := 1;
    while Position <= Length(Line) do
    begin
      if Comment = '{' then
      begin
        if Line[Position] = '}' then
          Comment := #0;
      end
      else if Comment = '(' then
      begin
        if (Line[Position] = '*') and (Position < Length(Line)) and (Line[Position + 1] = ')') then
        begin
          Comment := #0;
          Inc(Position);
        end;
      end
      else if InString then
      begin
        if Line[Position] = '''' then
          InString := False;
      end
      else
        case Line[Position] of
          '''':
            InString := True;
          '{':
            Comment := '{';
          '(':
            if (Position < Length(Line)) and (Line[Position + 1] = '*') then
            begin
              Comment := '(';
              Inc(Position);
            end;
          '/':
            if (Position < Length(Line)) and (Line[Position + 1] = '/') then
              Break;
          ';':
            if InUses then
            begin
              InUses := False;
              // Die Zeile mit dem Semikolon gehört noch zu uses.
              if Index < ALine then
                Section := BeforeUses;
            end;
        end;
      Inc(Position);
    end;
  end;
  Result := Section;
end;

class function TAtlasBreadcrumbs.ShortName(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

class function TAtlasBreadcrumbs.BadgeOf(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
  ANode: Integer): TAtlasBadge;
var
  Head: string;
begin
  case ANodes[ANode].Category of
    TAtlasOutlineCategory.TypeDecl:
      Result := MakeBadge(TAtlasBadgeKind.Type_, 'ty');
    TAtlasOutlineCategory.Field:
      Result := MakeBadge(TAtlasBadgeKind.Field, 'fd');
    TAtlasOutlineCategory.PropertyDecl:
      Result := MakeBadge(TAtlasBadgeKind.Property_, 'pp');
    TAtlasOutlineCategory.Constant, TAtlasOutlineCategory.EnumMember:
      Result := MakeBadge(TAtlasBadgeKind.Constant, 'co');
    TAtlasOutlineCategory.Method, TAtlasOutlineCategory.Routine:
      begin
        Head := '';
        if (ANodes[ANode].StartLine >= 0) and (ANodes[ANode].StartLine <= High(ALines)) then
          Head := LowerCase(TrimLeft(Copy(ALines[ANodes[ANode].StartLine], ANodes[ANode].StartCharacter + 1, MaxInt)));
        // class procedure/class function: das Wort nach class zählt.
        if Head.StartsWith('class ') then
          Head := TrimLeft(Copy(Head, 7, MaxInt));
        if Head.StartsWith('procedure') or Head.StartsWith('destructor') then
          Result := MakeBadge(TAtlasBadgeKind.Procedure_, 'pr')
        else
          Result := MakeBadge(TAtlasBadgeKind.Function_, 'fn');
      end;
  else
    Result := MakeBadge(TAtlasBadgeKind.Variable, 'va');
  end;
end;

function IsRoutine(const ANode: TAtlasOutlineNode): Boolean;
begin
  Result := ANode.Category in [TAtlasOutlineCategory.Method, TAtlasOutlineCategory.Routine];
end;

function IsSection(const ANode: TAtlasOutlineNode): Boolean;
begin
  Result := (ANode.Kind = KindNamespace) or (ANode.Category = TAtlasOutlineCategory.Section);
end;

function Contains(const ANode: TAtlasOutlineNode; ALine, ACharacter: Integer): Boolean;
begin
  Result := ((ALine > ANode.StartLine) or ((ALine = ANode.StartLine) and (ACharacter >= ANode.StartCharacter))) and
    ((ALine < ANode.EndLine) or ((ALine = ANode.EndLine) and (ACharacter <= ANode.EndCharacter)));
end;

/// <summary>Geschwister von ANode für das Sprungmenü.</summary>
function SiblingsOf(const ANodes: TAtlasOutlineNodes; ANode: Integer): TArray<Integer>;
var
  Parent, Index: Integer;
  Node: TAtlasOutlineNode;
  TopLevel: Boolean;

  function SameGroup(const AOther: TAtlasOutlineNode): Boolean;
  begin
    if Node.Category = TAtlasOutlineCategory.TypeDecl then
      Result := AOther.Category = TAtlasOutlineCategory.TypeDecl
    else if IsRoutine(Node) then
      Result := IsRoutine(AOther)
    else
      Result := AOther.Category in [TAtlasOutlineCategory.Constant, TAtlasOutlineCategory.Variable];
  end;

begin
  Result := nil;
  Node := ANodes[ANode];
  Parent := Node.Parent;
  TopLevel := (Parent < 0) or IsSection(ANodes[Parent]);
  for Index := 0 to High(ANodes) do
  begin
    if ANodes[Index].Hidden and not Node.InBody then
      Continue;
    if TopLevel then
    begin
      // Unit-Ebene: über interface und implementation hinweg.
      if ((ANodes[Index].Parent >= 0) and not IsSection(ANodes[ANodes[Index].Parent])) or IsSection(ANodes[Index]) or
        not SameGroup(ANodes[Index]) then
        Continue;
    end
    else
    begin
      if ANodes[Index].Parent <> Parent then
        Continue;
      // Methoden zeigen nur Methoden, lokale Routinen nur lokale Routinen.
      if IsRoutine(Node) and not IsRoutine(ANodes[Index]) then
        Continue;
    end;
    Result := Result + [Index];
  end;
end;

function NewCrumb(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ANode: Integer): TAtlasCrumb;
var
  Index: Integer;
begin
  Result.Text := TAtlasBreadcrumbs.ShortName(ANodes[ANode].Name);
  Result.Badge := TAtlasBreadcrumbs.BadgeOf(ANodes, ALines, ANode);
  Result.Node := ANode;
  Result.Siblings := SiblingsOf(ANodes, ANode);
  Result.Children := TAtlasBreadcrumbs.Children(ANodes, ANode);
  Result.Current := -1;
  for Index := 0 to High(Result.Siblings) do
    if Result.Siblings[Index] = ANode then
      Result.Current := Index;
end;

function TextCrumb(const AText: string; const ABadge: TAtlasBadge): TAtlasCrumb;
begin
  Result.Text := AText;
  Result.Badge := ABadge;
  Result.Node := -1;
  Result.Siblings := nil;
  Result.Current := -1;
  Result.Children := nil;
end;

/// <summary>Pfad von der Unit-Ebene bis ANode (einschließlich), ohne Abschnitte.</summary>
function Chain(const ANodes: TAtlasOutlineNodes; ANode: Integer): TArray<Integer>;
begin
  Result := nil;
  while ANode >= 0 do
  begin
    if not IsSection(ANodes[ANode]) then
      Result := [ANode] + Result;
    ANode := ANodes[ANode].Parent;
  end;
end;

class function TAtlasBreadcrumbs.Path(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ALine,
  ACharacter: Integer; const AUnitName: string; AShowUnit: Boolean): TAtlasCrumbs;
var
  Section: TAtlasCodeSection;
  Index, Inner, Item: Integer;
  Name, Owner: string;
  Parts: TArray<string>;
begin
  Result := nil;
  if AShowUnit and (AUnitName <> '') then
  begin
    Result := [TextCrumb(AUnitName, MakeBadge(TAtlasBadgeKind.Unit_, 'un'))];
    Result[0].Siblings := UnitMembers(ANodes);
    Result[0].Children := Result[0].Siblings;
  end;
  Section := SectionAt(ALines, ALine);
  Name := '';
  case Section of
    TAtlasCodeSection.UsesClause:
      Name := 'uses';
    TAtlasCodeSection.Initialization_:
      Name := 'initialization';
    TAtlasCodeSection.Finalization_:
      Name := 'finalization';
  end;
  if Name <> '' then
  begin
    Result := Result + [TextCrumb(Name, MakeBadge(TAtlasBadgeKind.Keyword, 'kw'))];
    Exit;
  end;
  // Innerster Knoten an der Stelle: Kinder stehen hinter ihren Eltern.
  Inner := -1;
  for Index := 0 to High(ANodes) do
    if not IsSection(ANodes[Index]) and Contains(ANodes[Index], ALine, ACharacter) then
      Inner := Index;
  if Inner < 0 then
    Exit;
  for Item in Chain(ANodes, Inner) do
  begin
    if ANodes[Item].Hidden and not ANodes[Item].InBody and (ANodes[Item].Declaration >= 0) then
    begin
      // Rumpf mit Deklaration: deren Typen und die Deklaration selbst.
      for Index in Chain(ANodes, ANodes[Item].Declaration) do
        Result := Result + [NewCrumb(ANodes, ALines, Index)];
    end
    else if not ANodes[Item].InBody and IsRoutine(ANodes[Item]) and (Pos('.', ANodes[Item].Name) > 0) then
    begin
      // Rumpf ohne Deklaration in der Unit (Klasse in einer anderen Unit): Besitzer als Text.
      Name := ANodes[Item].Name;
      Owner := Copy(Name, 1, LastDelimiter('.', Name) - 1);
      Parts := Owner.Split(['.']);
      for Owner in Parts do
        Result := Result + [TextCrumb(Owner, MakeBadge(TAtlasBadgeKind.Type_, 'ty'))];
      Result := Result + [NewCrumb(ANodes, ALines, Item)];
    end
    else
      Result := Result + [NewCrumb(ANodes, ALines, Item)];
  end;
end;

class function TAtlasBreadcrumbs.UnitMembers(const ANodes: TAtlasOutlineNodes): TArray<Integer>;
var
  Index, Parent: Integer;
begin
  Result := nil;
  for Index := 0 to High(ANodes) do
  begin
    Parent := ANodes[Index].Parent;
    if ANodes[Index].Hidden or IsSection(ANodes[Index]) or ((Parent >= 0) and not IsSection(ANodes[Parent])) then
      Continue;
    Result := Result + [Index];
  end;
end;

class function TAtlasBreadcrumbs.Routines(const ANodes: TAtlasOutlineNodes): TArray<Integer>;
var
  Index, Parent: Integer;
begin
  Result := nil;
  for Index := 0 to High(ANodes) do
  begin
    if ANodes[Index].Hidden or ANodes[Index].InBody or not IsRoutine(ANodes[Index]) then
      Continue;
    // Lokale Routinen (Eltern ist eine Routine) nicht.
    Parent := ANodes[Index].Parent;
    if (Parent >= 0) and IsRoutine(ANodes[Parent]) then
      Continue;
    Result := Result + [Index];
  end;
end;

class function TAtlasBreadcrumbs.QualifiedName(const ANodes: TAtlasOutlineNodes; ANode: Integer): string;
var
  Owner: Integer;
begin
  if (ANode < 0) or (ANode > High(ANodes)) then
    Exit('');
  Result := ANodes[ANode].Name;
  // Rümpfe tragen den Besitzer schon im Namen („TFoo.Bar“).
  if Pos('.', Result) > 0 then
    Exit;
  Owner := ANodes[ANode].Parent;
  while (Owner >= 0) and (ANodes[Owner].Category = TAtlasOutlineCategory.TypeDecl) do
  begin
    Result := ANodes[Owner].Name + '.' + Result;
    Owner := ANodes[Owner].Parent;
  end;
end;

class function TAtlasBreadcrumbs.Children(const ANodes: TAtlasOutlineNodes; ANode: Integer): TArray<Integer>;
var
  Owner, Index: Integer;
  Routine: Boolean;
begin
  Result := nil;
  if (ANode < 0) or (ANode > High(ANodes)) then
    Exit;
  // Bei Routinen liegen die lokalen Routinen im Rumpf, nicht an der Deklaration.
  Owner := Target(ANodes, ANode, True);
  Routine := IsRoutine(ANodes[Owner]);
  for Index := 0 to High(ANodes) do
  begin
    if ANodes[Index].Parent <> Owner then
      Continue;
    if Routine then
    begin
      // Nur lokale Routinen, keine lokalen Variablen und Konstanten.
      if not IsRoutine(ANodes[Index]) then
        Continue;
    end
    else if ANodes[Index].Hidden then
      Continue;
    Result := Result + [Index];
  end;
end;

class function TAtlasBreadcrumbs.Target(const ANodes: TAtlasOutlineNodes; ANode: Integer;
  AImplementation: Boolean): Integer;
begin
  Result := ANode;
  if (ANode < 0) or (ANode > High(ANodes)) then
    Exit(-1);
  if AImplementation then
  begin
    if ANodes[ANode].Body >= 0 then
      Result := ANodes[ANode].Body;
  end
  else if ANodes[ANode].Declaration >= 0 then
    Result := ANodes[ANode].Declaration;
end;

class function TAtlasBreadcrumbs.MatchesAtWordStart(const APattern, AName: string): Boolean;
var
  Index: Integer;
begin
  if APattern = '' then
    Exit(True);
  if TAtlasCompletionMatcher.Score(APattern, AName) >= TAtlasCompletionMatcher.ScoreWordStarts then
    Exit(True);
  for Index := 2 to Length(AName) - Length(APattern) + 1 do
    if TAtlasCompletionMatcher.IsWordStart(AName, Index) and SameText(Copy(AName, Index, Length(APattern)),
      APattern) then
      Exit(True);
  Result := False;
end;

class function TAtlasBreadcrumbs.Filter(const ANodes: TAtlasOutlineNodes; const ASiblings: TArray<Integer>;
  const APattern: string): TArray<Integer>;
var
  Item: Integer;
begin
  Result := nil;
  for Item in ASiblings do
    if MatchesAtWordStart(APattern, ShortName(ANodes[Item].Name)) then
      Result := Result + [Item];
end;

end.
