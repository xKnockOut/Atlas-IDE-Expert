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
// - Im Deklarationsteil einer Klasse, eines Records, Objekts oder Helfers
//   steht hinter dem Typ der Sichtbarkeitsabschnitt am Caret (#1759,
//   TAtlasVisibilitySectionFinder): Sein Menü listet die Abschnitte des Typs
//   als Sprungziele (Places), seine Kinder sind die Mitglieder des
//   Abschnitts. Vor dem ersten Schlüsselwort steht die implizite
//   Sichtbarkeit (Implicit).

interface

uses
  System.SysUtils,
  Atlas.Core.Style.Palette,
  Atlas.Core.Completion.Presentation,
  Atlas.Core.Outline.Model;

type
  /// <summary>Sprungziel eines Glieds ohne Knoten der Gliederung (Sichtbarkeitsabschnitt, #1759).</summary>
  TAtlasCrumbPlace = record
    Text: string;
    /// <summary>Position, 0-basiert.</summary>
    Line: Integer;
    Character: Integer;
  end;

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
    /// <summary>Sprungziele für das Menü, wenn das Glied keinen Knoten hat (Sichtbarkeitsabschnitte); Current
    /// ist dann der Index darin.</summary>
    Places: TArray<TAtlasCrumbPlace>;
    /// <summary>Das Glied steht für etwas, das nicht im Quelltext steht (implizite Sichtbarkeit).</summary>
    Implicit: Boolean;
  end;

  TAtlasCrumbs = TArray<TAtlasCrumb>;

  TAtlasBreadcrumbs = class
  public
    /// <summary>Abschnitt der Zeile ALine (0-basiert): Schlüsselwörter am Zeilenanfang (Spalte 1), uses bis zum
    /// abschließenden Semikolon; Kommentare und Strings zählen nicht.</summary>
    class function SectionAt(const ALines: TArray<string>; ALine: Integer): TAtlasCodeSection; static;
    /// <summary>Pfad am Caret (0-basiert). AUnitName steht vorn, wenn AShowUnit; mit AShowVisibility der
    /// Sichtbarkeitsabschnitt hinter dem Typ (#1759).</summary>
    class function Path(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ALine,
      ACharacter: Integer; const AUnitName: string; AShowUnit: Boolean;
      AShowVisibility: Boolean = False): TAtlasCrumbs; static;
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
    /// <summary>Hat das Glied ein Sprungmenü (Geschwister oder Sprungziele)?</summary>
    class function HasMenu(const ACrumb: TAtlasCrumb): Boolean; static;
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
  Atlas.Core.Completion.Matching,
  Atlas.Core.Outline.VisibilitySections;

const
  cKindNamespace = 3;

function MakeBadge(AKind: TAtlasBadgeKind; const ACode: string): TAtlasBadge;
begin
  Result.Kind := AKind;
  Result.Code := ACode;
end;

/// <summary>Wort am Anfang der Zeile (Spalte 1), klein; leer, wenn die Zeile mit Leerraum oder einem anderen
/// Zeichen beginnt.</summary>
function LeadingWord(const ALine: string): string;
var
  mIndex: Integer;
begin
  mIndex := 1;
  while (mIndex <= Length(ALine)) and CharInSet(ALine[mIndex], ['a'..'z', 'A'..'Z', '_']) do
  begin
    Inc(mIndex);
  end;
  Result := LowerCase(Copy(ALine, 1, mIndex - 1));
end;

/// <summary>Abschnitt nach dem Schlüsselwort AWord am Zeilenanfang; sonst ACurrent.</summary>
function SectionOfWord(const AWord, ALine: string; ACurrent: TAtlasCodeSection): TAtlasCodeSection;
begin
  Result := ACurrent;
  if AWord = 'interface' then
  begin
    Result := TAtlasCodeSection.InterfacePart;
  end
  else if AWord = 'implementation' then
  begin
    Result := TAtlasCodeSection.ImplementationPart;
  end
  else if AWord = 'initialization' then
  begin
    Result := TAtlasCodeSection.Initialization_;
  end
  else if AWord = 'finalization' then
  begin
    Result := TAtlasCodeSection.Finalization_;
  end
  else if (AWord = 'end') and (Copy(ALine, 4, 1) = '.') then
  begin
    Result := TAtlasCodeSection.None;
  end;
end;

function NextIs(const ALine: string; APos: Integer; AChar: Char): Boolean;
begin
  Result := (APos < Length(ALine)) and (ALine[APos + 1] = AChar);
end;

/// <summary>Im Kommentar AComment ('{' oder '(' für (* *)): schließt er an APos, wird AComment #0.</summary>
procedure CloseComment(const ALine: string; var APos: Integer; var AComment: Char);
begin
  if (AComment = '{') and (ALine[APos] = '}') then
  begin
    AComment := #0;
  end
  else if (AComment = '(') and (ALine[APos] = '*') and NextIs(ALine, APos, ')') then
  begin
    AComment := #0;
    Inc(APos);
  end;
end;

/// <summary>Zeichen an APos im Code: öffnet String oder Kommentar, merkt ein Semikolon. False bei //, dann zählt
/// der Rest der Zeile nicht.</summary>
function CodeChar(const ALine: string; var APos: Integer; var AComment: Char; var AInString: Boolean;
  var ASemicolon: Boolean): Boolean;
begin
  Result := True;
  case ALine[APos] of
    '''':
      AInString := True;
    '{':
      AComment := '{';
    '(':
      if NextIs(ALine, APos, '*') then
      begin
        AComment := '(';
        Inc(APos);
      end;
    '/':
      Result := not NextIs(ALine, APos, '/');
    ';':
      ASemicolon := True;
  end;
end;

/// <summary>Kommentare über Zeilen (AComment, #0 = keiner) mitführen; ASemicolon: ein Semikolon außerhalb von
/// Kommentaren und Strings.</summary>
procedure ScanLine(const ALine: string; var AComment: Char; out ASemicolon: Boolean);
var
  mPos: Integer;
  mInString: Boolean;
begin
  ASemicolon := False;
  mInString := False;
  mPos := 1;
  while mPos <= Length(ALine) do
  begin
    if AComment <> #0 then
    begin
      CloseComment(ALine, mPos, AComment);
    end
    else if mInString then
    begin
      mInString := ALine[mPos] <> '''';
    end
    else if not CodeChar(ALine, mPos, AComment, mInString, ASemicolon) then
    begin
      Break;
    end;
    Inc(mPos);
  end;
end;

class function TAtlasBreadcrumbs.SectionAt(const ALines: TArray<string>; ALine: Integer): TAtlasCodeSection;
var
  mIndex: Integer;
  mLine, mWord: string;
  mBeforeUses: TAtlasCodeSection;
  mInUses, mSemicolon: Boolean;
  mComment: Char;
begin
  Result := TAtlasCodeSection.None;
  mBeforeUses := TAtlasCodeSection.None;
  mInUses := False;
  // Offener Kommentar über Zeilen: '{' oder '(' für (* *); #0 = keiner.
  mComment := #0;
  for mIndex := 0 to Min(ALine, High(ALines)) do
  begin
    mLine := ALines[mIndex];
    if (mComment = #0) and not mInUses then
    begin
      mWord := LeadingWord(mLine);
      mInUses := mWord = 'uses';
      if mInUses then
      begin
        mBeforeUses := Result;
        Result := TAtlasCodeSection.UsesClause;
      end
      else
      begin
        Result := SectionOfWord(mWord, mLine, Result);
      end;
    end;
    ScanLine(mLine, mComment, mSemicolon);
    if mInUses and mSemicolon then
    begin
      mInUses := False;
      // Die Zeile mit dem Semikolon gehört noch zu uses.
      if mIndex < ALine then
      begin
        Result := mBeforeUses;
      end;
    end;
  end;
end;

class function TAtlasBreadcrumbs.HasMenu(const ACrumb: TAtlasCrumb): Boolean;
begin
  Result := (Length(ACrumb.Siblings) > 0) or (Length(ACrumb.Places) > 0);
end;

class function TAtlasBreadcrumbs.ShortName(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

class function TAtlasBreadcrumbs.BadgeOf(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
  ANode: Integer): TAtlasBadge;
var
  mHead: string;
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
        mHead := '';
        if (ANodes[ANode].StartLine >= 0) and (ANodes[ANode].StartLine <= High(ALines)) then
        begin
          mHead := LowerCase(TrimLeft(Copy(ALines[ANodes[ANode].StartLine], ANodes[ANode].StartCharacter + 1, MaxInt)));
        end;
        // class procedure/class function: das Wort nach class zählt.
        if mHead.StartsWith('class ') then
        begin
          mHead := TrimLeft(Copy(mHead, 7, MaxInt));
        end;
        if mHead.StartsWith('procedure') or mHead.StartsWith('destructor') then
        begin
          Result := MakeBadge(TAtlasBadgeKind.Procedure_, 'pr');
        end
        else
        begin
          Result := MakeBadge(TAtlasBadgeKind.Function_, 'fn');
        end;
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
  Result := (ANode.Kind = cKindNamespace) or (ANode.Category = TAtlasOutlineCategory.Section);
end;

function Contains(const ANode: TAtlasOutlineNode; ALine, ACharacter: Integer): Boolean;
begin
  Result := ((ALine > ANode.StartLine) or ((ALine = ANode.StartLine) and (ACharacter >= ANode.StartCharacter))) and
    ((ALine < ANode.EndLine) or ((ALine = ANode.EndLine) and (ACharacter <= ANode.EndCharacter)));
end;

/// <summary>Gehört AOther zur selben Gruppe wie ANode: Typen, Routinen bzw. Konstanten und Variablen.</summary>
function SameGroup(const ANode, AOther: TAtlasOutlineNode): Boolean;
begin
  if ANode.Category = TAtlasOutlineCategory.TypeDecl then
  begin
    Result := AOther.Category = TAtlasOutlineCategory.TypeDecl;
  end
  else if IsRoutine(ANode) then
  begin
    Result := IsRoutine(AOther);
  end
  else
  begin
    Result := AOther.Category in [TAtlasOutlineCategory.Constant, TAtlasOutlineCategory.Variable];
  end;
end;

/// <summary>Ist AIndex ein Geschwister von ANode? ATopLevel: Unit-Ebene über interface und implementation hinweg.
/// </summary>
function IsSibling(const ANodes: TAtlasOutlineNodes; ANode, AIndex: Integer; ATopLevel: Boolean): Boolean;
var
  mNode, mOther: TAtlasOutlineNode;
begin
  mNode := ANodes[ANode];
  mOther := ANodes[AIndex];
  if mOther.Hidden and not mNode.InBody then
  begin
    Exit(False);
  end;
  if ATopLevel then
  begin
    Result := ((mOther.Parent < 0) or IsSection(ANodes[mOther.Parent])) and not IsSection(mOther) and
      SameGroup(mNode, mOther);
  end
  else
  begin
    // Methoden zeigen nur Methoden, lokale Routinen nur lokale Routinen.
    Result := (mOther.Parent = mNode.Parent) and (not IsRoutine(mNode) or IsRoutine(mOther));
  end;
end;

/// <summary>Geschwister von ANode für das Sprungmenü.</summary>
function SiblingsOf(const ANodes: TAtlasOutlineNodes; ANode: Integer): TArray<Integer>;
var
  mParent, mIndex: Integer;
  mTopLevel: Boolean;
begin
  Result := nil;
  mParent := ANodes[ANode].Parent;
  mTopLevel := (mParent < 0) or IsSection(ANodes[mParent]);
  for mIndex := 0 to High(ANodes) do
  begin
    if IsSibling(ANodes, ANode, mIndex, mTopLevel) then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

function NewCrumb(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ANode: Integer): TAtlasCrumb;
var
  mIndex: Integer;
begin
  Result := Default(TAtlasCrumb);
  Result.Text := TAtlasBreadcrumbs.ShortName(ANodes[ANode].Name);
  Result.Badge := TAtlasBreadcrumbs.BadgeOf(ANodes, ALines, ANode);
  Result.Node := ANode;
  Result.Siblings := SiblingsOf(ANodes, ANode);
  Result.Children := TAtlasBreadcrumbs.Children(ANodes, ANode);
  Result.Current := -1;
  for mIndex := 0 to High(Result.Siblings) do
  begin
    if Result.Siblings[mIndex] = ANode then
    begin
      Result.Current := mIndex;
    end;
  end;
end;

function TextCrumb(const AText: string; const ABadge: TAtlasBadge): TAtlasCrumb;
begin
  Result := Default(TAtlasCrumb);
  Result.Text := AText;
  Result.Badge := ABadge;
  Result.Node := -1;
  Result.Current := -1;
end;

/// <summary>Glied des Sichtbarkeitsabschnitts APlace (#1759): Abschnitte als Sprungziele, Mitglieder des
/// Abschnitts als Kinder; vor dem ersten Schlüsselwort die implizite Sichtbarkeit.</summary>
function VisibilityCrumb(const ANodes: TAtlasOutlineNodes; const APlace: TAtlasVisibilityPlace): TAtlasCrumb;
var
  mSection: TAtlasVisibilitySection;
  mPlace: TAtlasCrumbPlace;
begin
  Result := TextCrumb(APlace.Implicit, MakeBadge(TAtlasBadgeKind.Keyword, 'kw'));
  Result.Implicit := APlace.Current < 0;
  if not Result.Implicit then
  begin
    Result.Text := APlace.Sections[APlace.Current].Keyword;
  end;
  for mSection in APlace.Sections do
  begin
    mPlace.Text := mSection.Keyword;
    mPlace.Line := mSection.Line;
    mPlace.Character := mSection.Character;
    Result.Places := Result.Places + [mPlace];
  end;
  Result.Current := APlace.Current;
  Result.Children := TAtlasVisibilitySectionFinder.MembersOf(ANodes, APlace, APlace.Current);
end;

/// <summary>Pfad von der Unit-Ebene bis ANode (einschließlich), ohne Abschnitte.</summary>
function Chain(const ANodes: TAtlasOutlineNodes; ANode: Integer): TArray<Integer>;
begin
  Result := nil;
  while ANode >= 0 do
  begin
    if not IsSection(ANodes[ANode]) then
    begin
      Result := [ANode] + Result;
    end;
    ANode := ANodes[ANode].Parent;
  end;
end;

/// <summary>Name des Glieds für die Abschnitte uses, initialization und finalization; sonst ''.</summary>
function SectionCrumbName(ASection: TAtlasCodeSection): string;
begin
  case ASection of
    TAtlasCodeSection.UsesClause:
      Result := 'uses';
    TAtlasCodeSection.Initialization_:
      Result := 'initialization';
    TAtlasCodeSection.Finalization_:
      Result := 'finalization';
  else
    Result := '';
  end;
end;

/// <summary>Innerster Knoten an der Stelle (Kinder stehen hinter ihren Eltern); -1 ohne.</summary>
function InnerNode(const ANodes: TAtlasOutlineNodes; ALine, ACharacter: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ANodes) do
  begin
    if not IsSection(ANodes[mIndex]) and Contains(ANodes[mIndex], ALine, ACharacter) then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Glieder für den Knoten AItem der Kette.</summary>
function CrumbsOf(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; AItem: Integer): TAtlasCrumbs;
var
  mIndex: Integer;
  mName, mOwner: string;
begin
  Result := nil;
  if ANodes[AItem].Hidden and not ANodes[AItem].InBody and (ANodes[AItem].Declaration >= 0) then
  begin
    // Rumpf mit Deklaration: deren Typen und die Deklaration selbst.
    for mIndex in Chain(ANodes, ANodes[AItem].Declaration) do
    begin
      Result := Result + [NewCrumb(ANodes, ALines, mIndex)];
    end;
    Exit;
  end;
  if not ANodes[AItem].InBody and IsRoutine(ANodes[AItem]) and (Pos('.', ANodes[AItem].Name) > 0) then
  begin
    // Rumpf ohne Deklaration in der Unit (Klasse in einer anderen Unit): Besitzer als Text.
    mName := ANodes[AItem].Name;
    for mOwner in Copy(mName, 1, LastDelimiter('.', mName) - 1).Split(['.']) do
    begin
      Result := Result + [TextCrumb(mOwner, MakeBadge(TAtlasBadgeKind.Type_, 'ty'))];
    end;
  end;
  Result := Result + [NewCrumb(ANodes, ALines, AItem)];
end;

class function TAtlasBreadcrumbs.Path(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ALine,
  ACharacter: Integer; const AUnitName: string; AShowUnit: Boolean; AShowVisibility: Boolean): TAtlasCrumbs;
var
  mInner, mItem: Integer;
  mName: string;
  mPlace: TAtlasVisibilityPlace;
begin
  Result := nil;
  if AShowUnit and (AUnitName <> '') then
  begin
    Result := [TextCrumb(AUnitName, MakeBadge(TAtlasBadgeKind.Unit_, 'un'))];
    Result[0].Siblings := UnitMembers(ANodes);
    Result[0].Children := Result[0].Siblings;
  end;
  mName := SectionCrumbName(SectionAt(ALines, ALine));
  if mName <> '' then
  begin
    Result := Result + [TextCrumb(mName, MakeBadge(TAtlasBadgeKind.Keyword, 'kw'))];
    Exit;
  end;
  mInner := InnerNode(ANodes, ALine, ACharacter);
  if mInner < 0 then
  begin
    Exit;
  end;
  mPlace := Default(TAtlasVisibilityPlace);
  mPlace.TypeNode := -1;
  if AShowVisibility then
  begin
    mPlace := TAtlasVisibilitySectionFinder.At(ANodes, ALines, ALine, ACharacter);
  end;
  for mItem in Chain(ANodes, mInner) do
  begin
    Result := Result + CrumbsOf(ANodes, ALines, mItem);
    if mItem = mPlace.TypeNode then
    begin
      Result := Result + [VisibilityCrumb(ANodes, mPlace)];
    end;
  end;
end;

class function TAtlasBreadcrumbs.UnitMembers(const ANodes: TAtlasOutlineNodes): TArray<Integer>;
var
  mIndex, mParent: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(ANodes) do
  begin
    mParent := ANodes[mIndex].Parent;
    if ANodes[mIndex].Hidden or IsSection(ANodes[mIndex]) or ((mParent >= 0) and not IsSection(ANodes[mParent])) then
    begin
      Continue;
    end;
    Result := Result + [mIndex];
  end;
end;

class function TAtlasBreadcrumbs.Routines(const ANodes: TAtlasOutlineNodes): TArray<Integer>;
var
  mIndex, mParent: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(ANodes) do
  begin
    if ANodes[mIndex].Hidden or ANodes[mIndex].InBody or not IsRoutine(ANodes[mIndex]) then
    begin
      Continue;
    end;
    // Lokale Routinen (Eltern ist eine Routine) nicht.
    mParent := ANodes[mIndex].Parent;
    if (mParent >= 0) and IsRoutine(ANodes[mParent]) then
    begin
      Continue;
    end;
    Result := Result + [mIndex];
  end;
end;

class function TAtlasBreadcrumbs.QualifiedName(const ANodes: TAtlasOutlineNodes; ANode: Integer): string;
var
  mOwner: Integer;
begin
  if (ANode < 0) or (ANode > High(ANodes)) then
  begin
    Exit('');
  end;
  Result := ANodes[ANode].Name;
  // Rümpfe tragen den Besitzer schon im Namen („TFoo.Bar“).
  if Pos('.', Result) > 0 then
  begin
    Exit;
  end;
  mOwner := ANodes[ANode].Parent;
  while (mOwner >= 0) and (ANodes[mOwner].Category = TAtlasOutlineCategory.TypeDecl) do
  begin
    Result := ANodes[mOwner].Name + '.' + Result;
    mOwner := ANodes[mOwner].Parent;
  end;
end;

class function TAtlasBreadcrumbs.Children(const ANodes: TAtlasOutlineNodes; ANode: Integer): TArray<Integer>;
var
  mOwner, mIndex: Integer;
  mRoutine: Boolean;
begin
  Result := nil;
  if (ANode < 0) or (ANode > High(ANodes)) then
  begin
    Exit;
  end;
  // Bei Routinen liegen die lokalen Routinen im Rumpf, nicht an der Deklaration.
  mOwner := Target(ANodes, ANode, True);
  mRoutine := IsRoutine(ANodes[mOwner]);
  for mIndex := 0 to High(ANodes) do
  begin
    if ANodes[mIndex].Parent <> mOwner then
    begin
      Continue;
    end;
    if mRoutine then
    begin
      // Nur lokale Routinen, keine lokalen Variablen und Konstanten.
      if not IsRoutine(ANodes[mIndex]) then
      begin
        Continue;
      end;
    end
    else if ANodes[mIndex].Hidden then
    begin
      Continue;
    end;
    Result := Result + [mIndex];
  end;
end;

class function TAtlasBreadcrumbs.Target(const ANodes: TAtlasOutlineNodes; ANode: Integer;
  AImplementation: Boolean): Integer;
begin
  Result := ANode;
  if (ANode < 0) or (ANode > High(ANodes)) then
  begin
    Exit(-1);
  end;
  if AImplementation then
  begin
    if ANodes[ANode].Body >= 0 then
    begin
      Result := ANodes[ANode].Body;
    end;
  end
  else if ANodes[ANode].Declaration >= 0 then
  begin
    Result := ANodes[ANode].Declaration;
  end;
end;

class function TAtlasBreadcrumbs.MatchesAtWordStart(const APattern, AName: string): Boolean;
var
  mIndex: Integer;
begin
  if APattern = '' then
  begin
    Exit(True);
  end;
  if TAtlasCompletionMatcher.Score(APattern, AName) >= TAtlasCompletionMatcher.cScoreWordStarts then
  begin
    Exit(True);
  end;
  for mIndex := 2 to Length(AName) - Length(APattern) + 1 do
  begin
    if TAtlasCompletionMatcher.IsWordStart(AName, mIndex) and SameText(Copy(AName, mIndex, Length(APattern)),
      APattern) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasBreadcrumbs.Filter(const ANodes: TAtlasOutlineNodes; const ASiblings: TArray<Integer>;
  const APattern: string): TArray<Integer>;
var
  mItem: Integer;
begin
  Result := nil;
  for mItem in ASiblings do
  begin
    if MatchesAtWordStart(APattern, ShortName(ANodes[mItem].Name)) then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

end.
