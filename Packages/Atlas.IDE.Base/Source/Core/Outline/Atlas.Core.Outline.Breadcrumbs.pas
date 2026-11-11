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
//   Sichtbarkeit (Implicit). Die Sprungziele tragen Marke und
//   Mitgliederzahl des Abschnitts, SectionType nennt den Typ für „Neue Zeile
//   am Ende von …“ und „Abschnitt anlegen“ (#1768, TAtlasSectionEditor).
// - Dahinter steht der Unterblock am Caret (const, type, class var; #1767,
//   TAtlasMemberBlockFinder) mit den Unterblöcken des Abschnitts als
//   Sprungziele und seinen Mitgliedern als Kinder.
// - Im Rumpf einer Methode trägt deren Glied die Sichtbarkeitsmarke der
//   Deklaration (#1765, TAtlasOutline.VisibilityMark): genaue Sichtbarkeit
//   aus dem Abschnitt der Deklaration, sonst aus der Gliederung. Lokale
//   Routinen, Routinen ohne Klasse und Rümpfe ohne Deklaration in der Unit
//   bekommen keine Marke.
// - Auf Unit-Ebene stehen vor dem Pfad der Teil der Unit (interface,
//   implementation) und der Deklarationsblock am Caret (type, const, var,
//   resourcestring, threadvar, label, exports; #1766,
//   TAtlasDeclarationBlockFinder): Das Menü des Teils springt zu interface
//   und implementation, das des Blocks zu allen Blöcken der Unit (Group nennt
//   den Teil), Kinder sind die Elemente des Blocks.
// - Am Ende stehen die Bedingungszweige um den Caret ({$IFDEF …}, {$ELSE …};
//   #1763, TAtlasConditionalFinder), außen zuerst, mit den Teilen ihres
//   Blocks als Sprungziele; auch auf Unit-Ebene und in uses.
// - Hinter Unit bzw. Abschnitt (uses, interface, implementation …) steht die
//   innerste {$REGION} um den Caret (#1764, TAtlasRegionFinder); ihr Menü
//   listet alle Regionen der Unit mit Tiefe (Depth). Ohne Namen bleibt Text
//   leer, die Anzeige ergänzt ihn.
// - Im Rumpf stehen hinter der Routine try/except/finally und case mit Zweig
//   (#1769, TAtlasStatementFinder), höchstens die innersten drei, vor den
//   Bedingungszweigen.
// - Hat eine Routine Überladungen im selben Typ bzw. auf derselben Ebene,
//   tragen Overloads alle in Quelltextreihenfolge und Overload die Stelle
//   des Glieds darin (#1784, TAtlasOverloads); die Leiste zeigt „(2/3)“.
// - Interfaces nennt die Interface-Methoden, die ein Methodenglied erfüllt
//   (#1785); Path lässt das Feld leer, die IDE trägt es aus der Antwort des
//   Servers ein (TAtlasOutlineInterfaces.TargetsOf).
// - Drop legt fest, welche Glieder die Leiste bei Platzmangel zuerst weglässt:
//   die Rahmen im Rumpf, dann die übrigen zusätzlichen Glieder, dann von vorn.

interface

uses
  System.SysUtils,
  Atlas.Core.Style.Palette,
  Atlas.Core.Completion.Presentation,
  Atlas.Core.Outline.Model,
  Atlas.Core.Outline.Interfaces;

type
  /// <summary>Sprungziel eines Glieds ohne Knoten der Gliederung (Sichtbarkeitsabschnitt, #1759).</summary>
  TAtlasCrumbPlace = record
    Text: string;
    /// <summary>Gruppe im Menü (Teil der Unit bei Deklarationsblöcken, #1766); leer = keine.</summary>
    Group: string;
    /// <summary>Einrückung im Menü (verschachtelte Regionen, #1764); 0 = keine.</summary>
    Depth: Integer;
    /// <summary>Marke der Gliederung (−, #, +, ◆) bei Sichtbarkeitsabschnitten (#1768); leer = keine.</summary>
    Mark: string;
    /// <summary>Mitglieder des Sichtbarkeitsabschnitts (#1768); nur mit Mark.</summary>
    Count: Integer;
    /// <summary>Position, 0-basiert.</summary>
    Line: Integer;
    Character: Integer;
  end;

{$SCOPEDENUMS ON}
  TAtlasCodeSection = (None, InterfacePart, ImplementationPart, UsesClause, Initialization_, Finalization_);
  /// <summary>Zusätzliche Glieder: Sichtbarkeitsabschnitt (#1759), Unterblock in Typen (#1767),
  /// Sichtbarkeitsmarke am Methodenglied im implementation-Teil (#1765), Deklarationsblock der Unit (#1766),
  /// Bedingungszweig (#1763), Region (#1764), try/except/finally und case-Zweig (#1769), Zähler der
  /// Überladungen (#1784).</summary>
  TAtlasCrumbPart = (Visibility, MemberBlocks, VisibilityMark, DeclarationBlocks, Conditionals, Regions,
    Statements, Overloads);
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
    /// <summary>Sichtbarkeitsmarke vor dem Namen (−, #, +, ◆; #1765); leer = keine.</summary>
    Mark: string;
    /// <summary>Genaue Sichtbarkeit zur Marke („strict private“).</summary>
    MarkVisibility: string;
    /// <summary>Zeile der Deklaration zur Marke, 0-basiert; -1 ohne Marke.</summary>
    MarkLine: Integer;
    /// <summary>Typ, dessen Sichtbarkeitsabschnitt das Glied zeigt (#1768, für „Neue Zeile am Ende von …“ und
    /// „Abschnitt anlegen“); -1 bei anderen Gliedern.</summary>
    SectionType: Integer;
    /// <summary>Überladungen der Routine in Quelltextreihenfolge (#1784); leer ohne Überladung.</summary>
    Overloads: TArray<Integer>;
    /// <summary>Index von Node in Overloads; -1 ohne Überladung.</summary>
    Overload: Integer;
    /// <summary>Interface-Methoden, die die Methode erfüllt (#1785); leer ohne.</summary>
    Interfaces: TAtlasInterfaceTargets;
    /// <summary>Rang beim Kürzen der Leiste: höhere fallen zuerst weg (2 = Rahmen im Rumpf, 1 = übrige
    /// zusätzliche Glieder), 0 = erst danach von vorn.</summary>
    Drop: Integer;
  end;

  TAtlasCrumbs = TArray<TAtlasCrumb>;
  TAtlasCrumbParts = set of TAtlasCrumbPart;

  /// <summary>Was TAtlasBreadcrumbs.Path zeigt: Stelle am Caret (0-basiert); UnitName steht vorn, wenn ShowUnit;
  /// Parts nennt die zusätzlichen Glieder hinter dem Typ (Sichtbarkeitsabschnitt, Unterblock) und die
  /// Sichtbarkeitsmarke an Methodenrümpfen.</summary>
  TAtlasCrumbRequest = record
    Line: Integer;
    Character: Integer;
    UnitName: string;
    ShowUnit: Boolean;
    Parts: TAtlasCrumbParts;
    class function Create(ALine, ACharacter: Integer; const AUnitName: string; AShowUnit: Boolean;
      AParts: TAtlasCrumbParts): TAtlasCrumbRequest; static;
  end;

  TAtlasBreadcrumbs = class
  public
    /// <summary>Abschnitt der Zeile ALine (0-basiert): Schlüsselwörter am Zeilenanfang (Spalte 1), uses bis zum
    /// abschließenden Semikolon; Kommentare und Strings zählen nicht.</summary>
    class function SectionAt(const ALines: TArray<string>; ALine: Integer): TAtlasCodeSection; static;
    /// <summary>Pfad am Caret nach ARequest.</summary>
    class function Path(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
      const ARequest: TAtlasCrumbRequest): TAtlasCrumbs; static;
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
  Atlas.Core.Outline.Conditionals,
  Atlas.Core.Outline.DeclarationBlocks,
  Atlas.Core.Outline.MemberBlocks,
  Atlas.Core.Outline.Overloads,
  Atlas.Core.Outline.Regions,
  Atlas.Core.Outline.Statements,
  Atlas.Core.Outline.VisibilitySections;

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
  Result := TAtlasOutline.IsSection(ANode);
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
  Result.MarkLine := -1;
  Result.SectionType := -1;
  Result.Overload := -1;
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
  Result.MarkLine := -1;
  Result.SectionType := -1;
  Result.Overload := -1;
end;

/// <summary>Glied des Sichtbarkeitsabschnitts APlace (#1759): Abschnitte als Sprungziele, Mitglieder des
/// Abschnitts als Kinder; vor dem ersten Schlüsselwort die implizite Sichtbarkeit. Jedes Sprungziel trägt
/// Marke und Mitgliederzahl seines Abschnitts (#1768).</summary>
function VisibilityCrumb(const ANodes: TAtlasOutlineNodes; const APlace: TAtlasVisibilityPlace): TAtlasCrumb;
var
  mIndex: Integer;
  mSection: TAtlasVisibilitySection;
  mPlace: TAtlasCrumbPlace;
begin
  Result := TextCrumb(APlace.Implicit, MakeBadge(TAtlasBadgeKind.Keyword, 'kw'));
  Result.Implicit := APlace.Current < 0;
  if not Result.Implicit then
  begin
    Result.Text := APlace.Sections[APlace.Current].Keyword;
  end;
  for mIndex := 0 to High(APlace.Sections) do
  begin
    mSection := APlace.Sections[mIndex];
    mPlace := Default(TAtlasCrumbPlace);
    mPlace.Text := mSection.Keyword;
    mPlace.Line := mSection.Line;
    mPlace.Character := mSection.Character;
    mPlace.Mark := TAtlasOutline.VisibilityMark(TAtlasOutline.VisibilityOf(mSection.Keyword));
    mPlace.Count := Length(TAtlasVisibilitySectionFinder.MembersOf(ANodes, APlace, mIndex));
    Result.Places := Result.Places + [mPlace];
  end;
  Result.Current := APlace.Current;
  Result.SectionType := APlace.TypeNode;
  Result.Children := TAtlasVisibilitySectionFinder.MembersOf(ANodes, APlace, APlace.Current);
end;

/// <summary>Glied des Unterblocks am Caret (#1767): Unterblöcke des Abschnitts als Sprungziele, Mitglieder des
/// Blocks als Kinder.</summary>
function MemberBlockCrumb(const ANodes: TAtlasOutlineNodes; const APlace: TAtlasMemberBlockPlace): TAtlasCrumb;
var
  mBlock: TAtlasMemberBlock;
  mPlace: TAtlasCrumbPlace;
begin
  Result := TextCrumb(APlace.Blocks[APlace.Current].Keyword, MakeBadge(TAtlasBadgeKind.Keyword, 'kw'));
  for mBlock in APlace.Blocks do
  begin
    mPlace := Default(TAtlasCrumbPlace);
    mPlace.Text := mBlock.Keyword;
    mPlace.Line := mBlock.Line;
    mPlace.Character := mBlock.Character;
    Result.Places := Result.Places + [mPlace];
  end;
  Result.Current := APlace.Current;
  Result.Children := TAtlasMemberBlockFinder.MembersOf(ANodes, APlace, APlace.Current);
end;

/// <summary>Alle Glieder von ACrumbs fallen beim Kürzen mit Rang ADrop weg.</summary>
procedure Droppable(var ACrumbs: TAtlasCrumbs; ADrop: Integer);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ACrumbs) do
  begin
    ACrumbs[mIndex].Drop := ADrop;
  end;
end;

/// <summary>Glieder hinter dem Typ: Sichtbarkeitsabschnitt und Unterblock, soweit in AParts.</summary>
function TypePartCrumbs(const ANodes: TAtlasOutlineNodes; const AVisibility: TAtlasVisibilityPlace;
  const ABlock: TAtlasMemberBlockPlace; AParts: TAtlasCrumbParts): TAtlasCrumbs;
begin
  Result := nil;
  if TAtlasCrumbPart.Visibility in AParts then
  begin
    Result := Result + [VisibilityCrumb(ANodes, AVisibility)];
  end;
  if (TAtlasCrumbPart.MemberBlocks in AParts) and (ABlock.Current >= 0) then
  begin
    Result := Result + [MemberBlockCrumb(ANodes, ABlock)];
  end;
  Droppable(Result, 1);
end;

/// <summary>Sprungziel für das Schlüsselwort ABlock, in der Gruppe seines Teils.</summary>
function DeclarationPlace(const ABlock: TAtlasDeclarationBlock): TAtlasCrumbPlace;
begin
  Result := Default(TAtlasCrumbPlace);
  Result.Text := ABlock.Keyword;
  Result.Group := ABlock.Section;
  Result.Line := ABlock.Line;
  Result.Character := ABlock.Character;
end;

/// <summary>Glieder für Teil und Deklarationsblock am Caret (#1766); leer außerhalb eines Blocks. AAfterSection
/// steht hinter dem Teil (Region, #1764).</summary>
function DeclarationCrumbs(const ANodes: TAtlasOutlineNodes; const APlace: TAtlasDeclarationBlockPlace;
  const AAfterSection: TAtlasCrumbs): TAtlasCrumbs;
var
  mBlock: TAtlasDeclarationBlock;
  mCrumb: TAtlasCrumb;
  mIndex: Integer;
begin
  Result := nil;
  if APlace.Current < 0 then
  begin
    Exit;
  end;
  mBlock := APlace.Blocks[APlace.Current];
  if mBlock.Section <> '' then
  begin
    mCrumb := TextCrumb(mBlock.Section, MakeBadge(TAtlasBadgeKind.Keyword, 'kw'));
    for mIndex := 0 to High(APlace.Sections) do
    begin
      mCrumb.Places := mCrumb.Places + [DeclarationPlace(APlace.Sections[mIndex])];
      if APlace.Sections[mIndex].Keyword = mBlock.Section then
      begin
        mCrumb.Current := mIndex;
      end;
    end;
    Result := Result + [mCrumb];
  end;
  Result := Result + AAfterSection;
  mCrumb := TextCrumb(mBlock.Keyword, MakeBadge(TAtlasBadgeKind.Keyword, 'kw'));
  for mIndex := 0 to High(APlace.Blocks) do
  begin
    mCrumb.Places := mCrumb.Places + [DeclarationPlace(APlace.Blocks[mIndex])];
  end;
  mCrumb.Current := APlace.Current;
  mCrumb.Children := TAtlasDeclarationBlockFinder.MembersOf(ANodes, APlace, APlace.Current);
  Result := Result + [mCrumb];
  Droppable(Result, 1);
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

/// <summary>Text einer Sichtbarkeit der Gliederung („strict private“); leer bei None.</summary>
function VisibilityText(AVisibility: TAtlasOutlineVisibility): string;
begin
  case AVisibility of
    TAtlasOutlineVisibility.StrictPrivate:
      Result := 'strict private';
    TAtlasOutlineVisibility.Private:
      Result := 'private';
    TAtlasOutlineVisibility.StrictProtected:
      Result := 'strict protected';
    TAtlasOutlineVisibility.Protected:
      Result := 'protected';
    TAtlasOutlineVisibility.Public:
      Result := 'public';
    TAtlasOutlineVisibility.Published:
      Result := 'published';
  else
    Result := '';
  end;
end;

/// <summary>Genaue Sichtbarkeit der Methodendeklaration ADeclaration: Abschnitt im Typ (auch implizit), sonst die
/// Angabe der Gliederung.</summary>
function DeclaredVisibility(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
  ADeclaration: Integer): string;
var
  mPlace: TAtlasVisibilityPlace;
begin
  mPlace := TAtlasVisibilitySectionFinder.At(ANodes, ALines, ANodes[ADeclaration].NameLine,
    ANodes[ADeclaration].NameCharacter);
  if mPlace.TypeNode <> ANodes[ADeclaration].Parent then
  begin
    Result := VisibilityText(ANodes[ADeclaration].Visibility);
  end
  else if mPlace.Current >= 0 then
  begin
    Result := mPlace.Sections[mPlace.Current].Keyword;
  end
  else
  begin
    Result := mPlace.Implicit;
  end;
end;

/// <summary>Sichtbarkeitsmarke der Methodendeklaration ADeclaration am Glied ACrumb (#1765); Routinen ohne Klasse
/// bleiben ohne Marke.</summary>
procedure MarkVisibility(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ADeclaration: Integer;
  var ACrumb: TAtlasCrumb);
var
  mParent: Integer;
  mVisibility: string;
begin
  mParent := ANodes[ADeclaration].Parent;
  if (ANodes[ADeclaration].Category <> TAtlasOutlineCategory.Method) or (mParent < 0) or
    (ANodes[mParent].Category <> TAtlasOutlineCategory.TypeDecl) then
  begin
    Exit;
  end;
  mVisibility := DeclaredVisibility(ANodes, ALines, ADeclaration);
  ACrumb.Mark := TAtlasOutline.VisibilityMark(TAtlasOutline.VisibilityOf(mVisibility));
  if ACrumb.Mark <> '' then
  begin
    ACrumb.MarkVisibility := mVisibility;
    ACrumb.MarkLine := ANodes[ADeclaration].NameLine;
  end;
end;

/// <summary>Glieder für den Knoten AItem der Kette; AMark: Sichtbarkeitsmarke an Methodenrümpfen (#1765).</summary>
function CrumbsOf(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; AItem: Integer;
  AMark: Boolean): TAtlasCrumbs;
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
    if AMark and (Length(Result) > 0) then
    begin
      MarkVisibility(ANodes, ALines, ANodes[AItem].Declaration, Result[High(Result)]);
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

/// <summary>Glieder der Bedingungszweige um die Stelle (#1763), außen zuerst; Badge „if“.</summary>
function ConditionalCrumbs(const ALines: TArray<string>; ALine, ACharacter: Integer): TAtlasCrumbs;
var
  mBranch: TAtlasConditionalBranch;
  mPart: TAtlasConditionalPart;
  mCrumb: TAtlasCrumb;
  mPlace: TAtlasCrumbPlace;
begin
  Result := nil;
  for mBranch in TAtlasConditionalFinder.At(ALines, ALine, ACharacter) do
  begin
    mCrumb := TextCrumb(mBranch.Text, MakeBadge(TAtlasBadgeKind.Keyword, 'if'));
    for mPart in mBranch.Parts do
    begin
      mPlace := Default(TAtlasCrumbPlace);
      mPlace.Text := mPart.Text;
      mPlace.Line := mPart.Line;
      mPlace.Character := mPart.Character;
      mCrumb.Places := mCrumb.Places + [mPlace];
    end;
    mCrumb.Current := mBranch.Current;
    mCrumb.Drop := 1;
    Result := Result + [mCrumb];
  end;
end;

/// <summary>Glied der innersten Region um die Stelle (#1764); leer außerhalb.</summary>
function RegionCrumbs(const ALines: TArray<string>; ALine, ACharacter: Integer): TAtlasCrumbs;
var
  mPlace: TAtlasRegionPlace;
  mRegion: TAtlasRegionMark;
  mCrumbPlace: TAtlasCrumbPlace;
  mCrumb: TAtlasCrumb;
begin
  Result := nil;
  mPlace := TAtlasRegionFinder.At(ALines, ALine, ACharacter);
  if mPlace.Current < 0 then
  begin
    Exit;
  end;
  mCrumb := TextCrumb(mPlace.Regions[mPlace.Current].Name, MakeBadge(TAtlasBadgeKind.Keyword, 'rg'));
  for mRegion in mPlace.Regions do
  begin
    mCrumbPlace := Default(TAtlasCrumbPlace);
    mCrumbPlace.Text := mRegion.Name;
    mCrumbPlace.Line := mRegion.Line;
    mCrumbPlace.Character := mRegion.Character;
    mCrumbPlace.Depth := mRegion.Depth;
    mCrumb.Places := mCrumb.Places + [mCrumbPlace];
  end;
  mCrumb.Current := mPlace.Current;
  mCrumb.Drop := 1;
  Result := [mCrumb];
end;

/// <summary>Glieder für try/except/finally und case im Rumpf (#1769): die innersten drei, außen zuerst.</summary>
function StatementCrumbs(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; ALine,
  ACharacter: Integer): TAtlasCrumbs;
const
  cMaxStatements = 3;
var
  mFrame: TAtlasStatementFrame;
  mPart: TAtlasStatementPart;
  mCrumb: TAtlasCrumb;
  mPlace: TAtlasCrumbPlace;
begin
  Result := nil;
  for mFrame in TAtlasStatementFinder.At(ANodes, ALines, ALine, ACharacter) do
  begin
    mCrumb := TextCrumb(mFrame.Text, MakeBadge(TAtlasBadgeKind.Keyword, 'kw'));
    for mPart in mFrame.Parts do
    begin
      mPlace := Default(TAtlasCrumbPlace);
      mPlace.Text := mPart.Text;
      mPlace.Line := mPart.Line;
      mPlace.Character := mPart.Character;
      mCrumb.Places := mCrumb.Places + [mPlace];
    end;
    mCrumb.Current := mFrame.Current;
    mCrumb.Drop := 2;
    Result := Result + [mCrumb];
  end;
  if Length(Result) > cMaxStatements then
  begin
    Result := Copy(Result, Length(Result) - cMaxStatements, cMaxStatements);
  end;
end;

class function TAtlasCrumbRequest.Create(ALine, ACharacter: Integer; const AUnitName: string; AShowUnit: Boolean;
  AParts: TAtlasCrumbParts): TAtlasCrumbRequest;
begin
  Result.Line := ALine;
  Result.Character := ACharacter;
  Result.UnitName := AUnitName;
  Result.ShowUnit := AShowUnit;
  Result.Parts := AParts;
end;

/// <summary>Glied der Unit vorn, wenn ARequest.ShowUnit und ein Name da ist.</summary>
function UnitCrumbs(const ANodes: TAtlasOutlineNodes; const ARequest: TAtlasCrumbRequest): TAtlasCrumbs;
begin
  Result := nil;
  if ARequest.ShowUnit and (ARequest.UnitName <> '') then
  begin
    Result := [TextCrumb(ARequest.UnitName, MakeBadge(TAtlasBadgeKind.Unit_, 'un'))];
    Result[0].Siblings := TAtlasBreadcrumbs.UnitMembers(ANodes);
    Result[0].Children := Result[0].Siblings;
  end;
end;

/// <summary>Glieder vom Knoten AInner nach außen; am Typ die Glieder seines Abschnitts und Unterblocks.</summary>
function ChainCrumbs(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; AInner: Integer;
  const ARequest: TAtlasCrumbRequest): TAtlasCrumbs;
var
  mItem, mType: Integer;
  mPlace: TAtlasVisibilityPlace;
  mBlock: TAtlasMemberBlockPlace;
begin
  Result := nil;
  mPlace := Default(TAtlasVisibilityPlace);
  mBlock := Default(TAtlasMemberBlockPlace);
  mBlock.Current := -1;
  mType := -1;
  if ARequest.Parts * [TAtlasCrumbPart.Visibility, TAtlasCrumbPart.MemberBlocks] <> [] then
  begin
    mPlace := TAtlasVisibilitySectionFinder.At(ANodes, ALines, ARequest.Line, ARequest.Character);
    mType := mPlace.TypeNode;
  end;
  if (TAtlasCrumbPart.MemberBlocks in ARequest.Parts) and (mType >= 0) then
  begin
    mBlock := TAtlasMemberBlockFinder.At(ANodes, ALines, ARequest.Line, ARequest.Character);
  end;
  for mItem in Chain(ANodes, AInner) do
  begin
    Result := Result + CrumbsOf(ANodes, ALines, mItem, TAtlasCrumbPart.VisibilityMark in ARequest.Parts);
    if mItem = mType then
    begin
      Result := Result + TypePartCrumbs(ANodes, mPlace, mBlock, ARequest.Parts);
    end;
  end;
end;

/// <summary>Pfad ohne die Bedingungszweige (siehe TAtlasBreadcrumbs.Path).</summary>
function OutlinePath(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
  const ARequest: TAtlasCrumbRequest): TAtlasCrumbs;
var
  mInner: Integer;
  mName: string;
  mRegion, mDeclaration: TAtlasCrumbs;
begin
  mRegion := nil;
  if TAtlasCrumbPart.Regions in ARequest.Parts then
  begin
    mRegion := RegionCrumbs(ALines, ARequest.Line, ARequest.Character);
  end;
  Result := UnitCrumbs(ANodes, ARequest);
  mName := SectionCrumbName(TAtlasBreadcrumbs.SectionAt(ALines, ARequest.Line));
  if mName <> '' then
  begin
    Result := Result + [TextCrumb(mName, MakeBadge(TAtlasBadgeKind.Keyword, 'kw'))] + mRegion;
    Exit;
  end;
  mDeclaration := nil;
  if TAtlasCrumbPart.DeclarationBlocks in ARequest.Parts then
  begin
    mDeclaration := DeclarationCrumbs(ANodes, TAtlasDeclarationBlockFinder.At(ANodes, ALines, ARequest.Line),
      mRegion);
  end;
  if mDeclaration = nil then
  begin
    mDeclaration := mRegion;
  end;
  Result := Result + mDeclaration;
  mInner := InnerNode(ANodes, ARequest.Line, ARequest.Character);
  if mInner >= 0 then
  begin
    Result := Result + ChainCrumbs(ANodes, ALines, mInner, ARequest);
  end;
end;

/// <summary>Überladungen und Stelle an den Gliedern mit Routine (#1784).</summary>
procedure MarkOverloads(const ANodes: TAtlasOutlineNodes; var ACrumbs: TAtlasCrumbs);
var
  mIndex, mOverload: Integer;
begin
  for mIndex := 0 to High(ACrumbs) do
  begin
    ACrumbs[mIndex].Overloads := TAtlasOverloads.Find(ANodes, ACrumbs[mIndex].Node);
    for mOverload := 0 to High(ACrumbs[mIndex].Overloads) do
    begin
      if ACrumbs[mIndex].Overloads[mOverload] = ACrumbs[mIndex].Node then
      begin
        ACrumbs[mIndex].Overload := mOverload;
      end;
    end;
  end;
end;

class function TAtlasBreadcrumbs.Path(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>;
  const ARequest: TAtlasCrumbRequest): TAtlasCrumbs;
begin
  Result := OutlinePath(ANodes, ALines, ARequest);
  if TAtlasCrumbPart.Overloads in ARequest.Parts then
  begin
    MarkOverloads(ANodes, Result);
  end;
  if TAtlasCrumbPart.Statements in ARequest.Parts then
  begin
    Result := Result + StatementCrumbs(ANodes, ALines, ARequest.Line, ARequest.Character);
  end;
  if TAtlasCrumbPart.Conditionals in ARequest.Parts then
  begin
    Result := Result + ConditionalCrumbs(ALines, ARequest.Line, ARequest.Character);
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
