unit Atlas.Common.Editing.MoveClass;

// „Klasse in eigene Unit verschieben“ (#103 Teil B): Die Deklaration einer
// Klasse (oder eines Records) samt Attributen, Doku-Kommentar, Vorwärts-
// deklaration und allen Methodenrümpfen kommt in eine neue Unit.
//
// Die uses der neuen Unit entstehen aus den Bezeichnern, die der verschobene
// Code braucht: Was die Deklaration braucht, steht im interface, was nur die
// Rümpfe brauchen, im implementation. Braucht die Klasse Namen aus dem
// interface der Ursprungs-Unit, bindet die neue Unit diese ein; die Ursprungs-
// Unit erhält die neue Unit im uses des Abschnitts, in dem sie die Klasse
// noch verwendet.
//
// Nicht angeboten: Zugriff auf Namen aus dem implementation-Teil der
// Ursprungs-Unit, Kreisverweis zweier interface-Teile, Formularklassen,
// gleichnamige generische Typen, bedingte Übersetzung um die verschobenen
// Teile, ein Ergebnis, das nicht parst.
//
// Bezeichner ohne Namensauflösung (Lookup nil oder unbekannter Name): lokale
// Namen und Mitglieder der Klasse kennt die Unit selbst, ebenso die Namen der
// Ursprungs-Unit; für alles andere übernimmt die neue Unit die uses der
// Ursprungs-Unit.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Bedeutung eines Namens an einer Stelle der Ursprungs-Unit.</summary>
  TMoveClassMeaning = record
    Found: Boolean;
    /// <summary>Lokale Variable, Parameter, Typparameter: braucht kein uses.</summary>
    IsLocal: Boolean;
    /// <summary>Unit der Deklaration; '' ohne (eingebaute Namen).</summary>
    UnitName: string;
    /// <summary>Datei und Stelle der Deklaration.</summary>
    FileName: string;
    Position: TTextPosition;
  end;

  /// <summary>Löst ANames (z. B. ['System', 'Classes', 'TList']) an AOffset der Ursprungs-Unit auf.</summary>
  TMoveClassLookup = reference to function(ATree: TSyntaxTree; const AFileName: string;
    const ANames: TArray<string>; AOffset: Integer): TMoveClassMeaning;

  /// <summary>Ursprungs-Unit, aus der die Klasse wandert.</summary>
  TMoveClassSource = record
    FileName: string;
    Text: string;
    Tree: TSyntaxTree;
    /// <summary>Typkommentar über den Rümpfen ({ TKunde }) mitnehmen (#1838); Create setzt True.</summary>
    TypeComments: Boolean;
    class function Create(const AFileName, AText: string; ATree: TSyntaxTree): TMoveClassSource; static;
  end;

  /// <summary>Namen eines Verschiebens: Ursprungs-Unit, neue Unit, Klasse.</summary>
  TMoveClassNames = record
    OriginUnit: string;
    NewUnit: string;
    ClassName: string;
    class function Create(const AOriginUnit, ANewUnit, AClassName: string): TMoveClassNames; static;
  end;

  TMoveClassPlan = record
    ClassName: string;
    OriginUnit: string;
    NewUnit: string;
    /// <summary>Text der neuen Unit, Zeilenenden wie die Ursprungs-Unit.</summary>
    Text: string;
    /// <summary>Änderungen an der Ursprungs-Unit.</summary>
    OriginEdits: TArray<TTextEdit>;
    /// <summary>Die neue Unit bindet die Ursprungs-Unit ein.</summary>
    UsesOrigin: Boolean;
    /// <summary>Namen ohne bekannte Unit: Für sie übernimmt die neue Unit die uses der Ursprungs-Unit.</summary>
    Unresolved: TArray<string>;
    function Names: TMoveClassNames;
  end;

  TMoveClass = class
  public const
    cKind = 'refactor.move';
  public
    /// <summary>Klassen- oder Record-Deklaration, auf deren erster Zeile APosition steht; nil ohne.</summary>
    class function ClassAt(ATree: TSyntaxTree; const APosition: TTextPosition): TSyntaxNode; static;
    /// <summary>Vorgeschlagener Unit-Name: Klassenname ohne führendes T (TKunde → Kunde).</summary>
    class function DefaultUnitName(const AClassName: string): string; static;
    /// <summary>Neue Unit und Änderungen an der Ursprungs-Unit; False mit Grund, wenn nicht verschiebbar.</summary>
    class function Plan(const ASource: TMoveClassSource; const APosition: TTextPosition; const ANewUnit: string;
      const ALookup: TMoveClassLookup; out APlan: TMoveClassPlan; out AReason: string): Boolean; static;
    /// <summary>Änderungen an einer Unit, die die Klasse verwendet: qualifizierte Namen (Alt.TKunde) auf die neue
    /// Unit umstellen und, mit AAddUses, die neue Unit neben die Ursprungs-Unit ins uses. AReferences: Stellen
    /// aus der Referenzsuche; leer = jedes Vorkommen des Namens. False ohne Änderung.</summary>
    class function UpdateUser(const AText: string; ATree: TSyntaxTree; const ANames: TMoveClassNames;
      const AReferences: TArray<TTextRange>; AAddUses: Boolean; out AEdits: TArray<TTextEdit>): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.TypeComments,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TEditingMoveClassText = (NoClassAtThisPosition, IsNotAValidUnit, TheNewUnitWouldHave, TheUnitHasNoInterface,
    SeveralTypesAreNamed, PartOfTheClassIs, TheClassUsesFromThe, CircularReferenceTheClassNeeds, NoRoomForTheNew,
    TheOriginalUnitNoLonger, TheNewUnitDoesNot, FormClassesStayWithTheir);

const
  cTexts: array[TEditingMoveClassText] of TAtlasText = (
    (De: 'keine Klasse an dieser Stelle'; En: 'no class at this position'),
    (De: '„%s“ ist kein gültiger Unit-Name'; En: '“%s” is not a valid unit name'),
    (De: 'die neue Unit hieße wie die Ursprungs-Unit';
     En: 'the new unit would have the same name as the original unit'),
    (De: 'die Unit hat keinen interface- und implementation-Teil';
     En: 'the unit has no interface and implementation part'),
    (De: 'mehrere Typen heißen %s'; En: 'several types are named %s'),
    (De: 'ein Teil der Klasse steht in bedingter Übersetzung'; En: 'part of the class is in conditional compilation'),
    (De: 'die Klasse verwendet %s aus dem implementation-Teil von %s';
     En: 'the class uses %s from the implementation part of %s'),
    (De: 'Kreisverweis: die Klasse braucht Typen aus dem interface von %s, das sie selbst verwendet';
     En: 'circular reference: the class needs types from the interface of %s, which itself uses it'),
    (De: 'kein Platz für die neue Unit im uses'; En: 'no room for the new unit in uses'),
    (De: 'die Ursprungs-Unit parst danach nicht mehr'; En: 'the original unit no longer parses afterwards'),
    (De: 'die neue Unit parst nicht'; En: 'the new unit does not parse'),
    (De: 'Formularklassen bleiben bei ihrer Formulardatei'; En: 'Form classes stay with their form file'));

{$SCOPEDENUMS OFF}

const
  /// <summary>Namen aus System, die jede Unit ohne uses kennt; gelten auch ohne Namensauflösung als bekannt.
  /// </summary>
  cSystemNames: array[0..93] of string = ('string', 'Integer', 'Cardinal', 'ShortInt', 'SmallInt', 'LongInt',
    'Int64', 'Byte', 'Word', 'LongWord', 'UInt64', 'NativeInt', 'NativeUInt', 'Boolean', 'ByteBool', 'WordBool',
    'LongBool', 'Char', 'AnsiChar', 'WideChar', 'Single', 'Double', 'Extended', 'Real', 'Currency', 'Comp',
    'Pointer', 'PChar', 'AnsiString', 'WideString', 'UnicodeString', 'ShortString', 'RawByteString', 'UTF8String',
    'Variant', 'OleVariant', 'TObject', 'TClass', 'IInterface', 'IUnknown', 'TGUID', 'TArray', 'TDateTime',
    'True', 'False', 'Exit', 'Inc', 'Dec', 'Length', 'SetLength', 'High', 'Low', 'Ord', 'Chr', 'Assigned', 'Copy',
    'Pos', 'Insert', 'Delete', 'Trunc', 'Round', 'Abs', 'Sqr', 'SizeOf', 'Default', 'New', 'Dispose', 'FreeMem',
    'GetMem', 'Move', 'FillChar', 'Include', 'Exclude', 'Succ', 'Pred', 'Odd', 'Assert', 'Break', 'Continue',
    'Halt', 'TypeInfo', 'Write', 'Writeln', 'Read', 'Readln', 'Concat', 'Str', 'Val', 'Random', 'Randomize',
    'Initialize', 'Finalize', 'IsManagedType', 'GetTypeKind');

type
  TOffsetRange = record
    Start: Integer;
    Stop: Integer;
  end;

function CleanName(const AName: string): string;
begin
  Result := AName;
  if Result.StartsWith('&') then
  begin
    Result := Result.Substring(1);
  end;
end;

function MakeRange(AStart, AStop: Integer): TOffsetRange;
begin
  Result.Start := AStart;
  Result.Stop := AStop;
end;

function InRanges(const ARanges: TArray<TOffsetRange>; AOffset: Integer): Boolean;
var
  mItem: TOffsetRange;
begin
  for mItem in ARanges do
  begin
    if (AOffset >= mItem.Start) and (AOffset < mItem.Stop) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Typknoten einer Typdeklaration (ohne GenericParams); nil ohne.</summary>
function TypeNodeOf(ADecl: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ADecl.ChildCount - 1 do
  begin
    if ADecl[mIndex].Kind <> TSyntaxKind.GenericParams then
    begin
      Exit(ADecl[mIndex]);
    end;
  end;
  Result := nil;
end;

function IsSection(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection]);
end;

function IsMethodOf(ARoutine: TSyntaxNode; const AClassName: string): Boolean;
begin
  Result := (ARoutine.Kind = TSyntaxKind.RoutineDecl) and StartsText(AClassName + '.', ARoutine.Name);
end;

function UpperDirective(const AToken: TPascalToken): string;
begin
  Result := UpperCase(AToken.Text);
  if Result.StartsWith('{$') then
  begin
    Result := Result.Substring(2);
  end
  else if Result.StartsWith('(*$') then
  begin
    Result := Result.Substring(3);
  end
  else
  begin
    Result := '';
  end;
end;

/// <summary>+1 öffnet, -1 schließt, 2 verzweigt ({$ELSE}); 0 sonst.</summary>
function ConditionalStep(const AToken: TPascalToken): Integer;
var
  mText: string;
begin
  Result := 0;
  if AToken.Kind <> TPascalTokenKind.Directive then
  begin
    Exit;
  end;
  mText := UpperDirective(AToken);
  if StartsText('IFDEF', mText) or StartsText('IFNDEF', mText) or StartsText('IFOPT', mText) or
    StartsText('IF ', mText) or StartsText('IF(', mText) then
  begin
    Result := 1;
  end
  else if StartsText('ENDIF', mText) or StartsText('IFEND', mText) then
  begin
    Result := -1;
  end
  else if StartsText('ELSE', mText) then
  begin
    Result := 2;
  end;
end;

/// <summary>Bricht das Token an dieser Stelle den Bereich auf? Innen darf keine Bedingung offen sein und weder
/// {$ELSE} noch {$ENDIF} eine von außen fortsetzen.</summary>
function BreaksRange(AStep, ADepth: Integer; AInside: Boolean): Boolean;
begin
  Result := AInside and ((ADepth > 0) or (AStep = -1) or (AStep = 2));
end;

/// <summary>Tiefe der bedingten Übersetzung nach einem Schritt; überzählige {$ENDIF} zählen nicht.</summary>
function NextDepth(ADepth, AStep: Integer): Integer;
begin
  Result := ADepth;
  if AStep = 1 then
  begin
    Result := ADepth + 1;
  end
  else if (AStep = -1) and (ADepth > 0) then
  begin
    Result := ADepth - 1;
  end;
end;

/// <summary>Steht ARange außerhalb jeder bedingten Übersetzung und sind die Direktiven darin ausgeglichen?</summary>
function Unconditional(const ATokens: TArray<TPascalToken>; const ARange: TOffsetRange): Boolean;
var
  mIndex, mDepth, mStep: Integer;
begin
  mDepth := 0;
  for mIndex := 0 to High(ATokens) do
  begin
    if ATokens[mIndex].Offset >= ARange.Stop then
    begin
      Break;
    end;
    mStep := ConditionalStep(ATokens[mIndex]);
    if BreaksRange(mStep, mDepth, ATokens[mIndex].Offset >= ARange.Start) then
    begin
      Exit(False);
    end;
    mDepth := NextDepth(mDepth, mStep);
  end;
  Result := mDepth = 0;
end;

/// <summary>Ist der Text zwischen AFrom und ATo nur Leerraum?</summary>
function Blank(const AText: string; AFrom, ATo: Integer): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := AFrom + 1 to ATo do
  begin
    if not CharInSet(AText[mIndex], [' ', #9, #13, #10]) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

function BlankLine(const AText: string; const ALines: TLineTable; ALine: Integer): Boolean;
begin
  Result := (ALine >= 0) and (ALine < ALines.LineCount) and
    Blank(AText, ALines.LineStart(ALine), ALines.LineContentEnd(ALine));
end;

/// <summary>Beginn samt Kommentaren in den Zeilen direkt darüber.</summary>
function WithLeadingComments(const AText: string; const ALines: TLineTable; const ATokens: TArray<TPascalToken>;
  AStart: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := AStart;
  mIndex := TRoutineBody.TokenAt(ATokens, AStart);
  if mIndex < 0 then
  begin
    Exit;
  end;
  while (mIndex > 0) and (ATokens[mIndex - 1].Kind = TPascalTokenKind.Comment) and
    (ATokens[mIndex - 1].EndPos.Line >= ALines.PositionAt(Result).Line - 1) and
    Blank(AText, ALines.LineStart(ATokens[mIndex - 1].StartPos.Line), ATokens[mIndex - 1].Offset) do
  begin
    Dec(mIndex);
    Result := ATokens[mIndex].Offset;
  end;
end;

/// <summary>Typkommentar der Klasse AClassName ({ TKunde }, // TKunde, Trennlinie) über der Zeile AFirstLine, mit
/// Leerzeilen dazwischen (#1838); Start = Stop ohne. Regionen bleiben, ihr Ende stünde sonst allein.</summary>
function TypeHeaderRange(const ASource: TMoveClassSource; const ALines: TLineTable; AFirstLine: Integer;
  const AClassName: string): TOffsetRange;
var
  mComment: TTypeComment;
begin
  Result := MakeRange(0, 0);
  if not ASource.TypeComments then
  begin
    Exit;
  end;
  mComment := TTypeComments.Find(TTextLines.SplitLines(ASource.Text), AFirstLine, AFirstLine, AClassName);
  if mComment.Found and (mComment.Style <> TTypeCommentStyle.Region) and (mComment.Last < AFirstLine) then
  begin
    Result := MakeRange(ALines.LineStart(mComment.First), ALines.LineContentEnd(mComment.Last));
  end;
end;

/// <summary>Bereich zum Entfernen: ganze Zeilen, wenn das Stück allein darauf steht, samt einer Leerzeile
/// dahinter, wenn davor auch eine steht.</summary>
function RemovalRange(const AText: string; const ALines: TLineTable; const APiece: TOffsetRange): TOffsetRange;
var
  mFirst, mLast: Integer;
begin
  Result := APiece;
  mFirst := ALines.PositionAt(APiece.Start).Line;
  mLast := ALines.PositionAt(APiece.Stop).Line;
  if not Blank(AText, ALines.LineStart(mFirst), APiece.Start) or
    not Blank(AText, APiece.Stop, ALines.LineContentEnd(mLast)) then
  begin
    Exit;
  end;
  Result.Start := ALines.LineStart(mFirst);
  Result.Stop := ALines.LineStart(mLast + 1);
  if (mLast + 1 < ALines.LineCount) and BlankLine(AText, ALines, mFirst - 1) and
    BlankLine(AText, ALines, mLast + 1) then
  begin
    Result.Stop := ALines.LineStart(mLast + 2);
  end;
end;

/// <summary>Text eines Stücks ab Zeilenanfang (Einrückung bleibt), wenn davor nur Leerraum steht.</summary>
function PieceText(const AText: string; const ALines: TLineTable; const APiece: TOffsetRange): string;
var
  mStart: Integer;
begin
  mStart := ALines.LineStart(ALines.PositionAt(APiece.Start).Line);
  if not Blank(AText, mStart, APiece.Start) then
  begin
    mStart := APiece.Start;
  end;
  Result := Copy(AText, mStart + 1, APiece.Stop - mStart);
end;

procedure AddUnique(var AList: TArray<string>; const AName: string);
var
  mItem: string;
begin
  for mItem in AList do
  begin
    if SameText(mItem, AName) then
    begin
      Exit;
    end;
  end;
  AList := AList + [AName];
end;

function Contains(const AList: TArray<string>; const AName: string): Boolean;
var
  mItem: string;
begin
  for mItem in AList do
  begin
    if SameText(mItem, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure AddName(ANames: TDictionary<string, Integer>; const AName: string; AOffset: Integer);
begin
  if not ANames.ContainsKey(LowerCase(Trim(AName))) then
  begin
    ANames.Add(LowerCase(Trim(AName)), AOffset);
  end;
end;

/// <summary>Werte eines Aufzählungstyps; andere Typen haben keine.</summary>
procedure AddEnumValues(ANames: TDictionary<string, Integer>; ADecl: TSyntaxNode);
var
  mTypeNode: TSyntaxNode;
  mItem: Integer;
begin
  mTypeNode := TypeNodeOf(ADecl);
  if (mTypeNode = nil) or (mTypeNode.Kind <> TSyntaxKind.EnumType) then
  begin
    Exit;
  end;
  for mItem := 0 to mTypeNode.ChildCount - 1 do
  begin
    if mTypeNode[mItem].Kind = TSyntaxKind.Identifier then
    begin
      AddName(ANames, mTypeNode[mItem].Name, mTypeNode[mItem].StartOffset);
    end;
  end;
end;

/// <summary>Namen eines type-, const- oder var-Abschnitts.</summary>
procedure AddDeclarations(ANames: TDictionary<string, Integer>; ASection: TSyntaxNode);
var
  mIndex: Integer;
  mChild: TSyntaxNode;
  mName: string;
begin
  for mIndex := 0 to ASection.ChildCount - 1 do
  begin
    mChild := ASection[mIndex];
    if not (mChild.Kind in [TSyntaxKind.TypeDecl, TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl]) then
    begin
      Continue;
    end;
    for mName in mChild.Name.Split([',']) do
    begin
      AddName(ANames, mName, mChild.StartOffset);
    end;
    if mChild.Kind = TSyntaxKind.TypeDecl then
    begin
      AddEnumValues(ANames, mChild);
    end;
  end;
end;

/// <summary>Namen der Deklarationen auf oberster Ebene mit Offset (Typen, Aufzählungswerte, Konstanten,
/// Variablen, Routinen; ohne Methodenrümpfe).</summary>
procedure CollectTopLevel(ASection: TSyntaxNode; ANames: TDictionary<string, Integer>);
var
  mIndex: Integer;
  mNode: TSyntaxNode;
begin
  for mIndex := 0 to ASection.ChildCount - 1 do
  begin
    mNode := ASection[mIndex];
    case mNode.Kind of
      TSyntaxKind.TypeSection, TSyntaxKind.ConstSection, TSyntaxKind.VarSection:
        AddDeclarations(ANames, mNode);
      TSyntaxKind.RoutineDecl:
        if Pos('.', mNode.Name) = 0 then
        begin
          AddName(ANames, mNode.Name, mNode.StartOffset);
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;
end;

/// <summary>Namen, die ohne uses bekannt sind: Mitglieder und Typparameter der Klasse, Parameter, Variablen
/// und Konstanten der Methoden samt Result und Self.</summary>
procedure CollectOwnNames(ANode: TSyntaxNode; ANames: TDictionary<string, Boolean>);
var
  mNames: TDictionary<string, Boolean>;
begin
  mNames := ANames;
  // Walk statt Rekursion. Laufvariablen „for var I“ stehen als InlineVar im for.
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    var
      Index: Integer;
      Name: string;
    begin
      case AChild.Kind of
        TSyntaxKind.Field, TSyntaxKind.PropertyDecl, TSyntaxKind.RoutineHeader, TSyntaxKind.TypeDecl,
        TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl, TSyntaxKind.Parameter, TSyntaxKind.InlineVar,
        TSyntaxKind.InlineConst, TSyntaxKind.RoutineDecl:
          for Name in AChild.Name.Split([',']) do
          begin
            if (Trim(Name) <> '') and (Pos('.', Name) = 0) then
            begin
              mNames.AddOrSetValue(LowerCase(Trim(Name)), True);
            end;
          end;
        TSyntaxKind.GenericParams:
          for Index := 0 to AChild.ChildCount - 1 do
          begin
            mNames.AddOrSetValue(LowerCase(AChild[Index].Name), True);
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
      Result := True;
    end);
end;

/// <summary>Name eines Attributs: [Weak] bzw. [Fixture('x')].</summary>
function IsAttributeName(ANode: TSyntaxNode): Boolean;
var
  mParent: TSyntaxNode;
begin
  mParent := ANode.Parent;
  Result := (ANode.Kind = TSyntaxKind.Identifier) and (mParent <> nil) and
    ((mParent.Kind = TSyntaxKind.Attribute) or ((mParent.Kind = TSyntaxKind.Call) and (mParent[0] = ANode) and
    (mParent.Parent <> nil) and (mParent.Parent.Kind = TSyntaxKind.Attribute)));
end;

type
  TNeed = record
    Names: TArray<string>;
    Node: TSyntaxNode;
  end;

procedure CollectNeeds(ANode: TSyntaxNode; var ANeeds: TArray<TNeed>);
var
  mNeeds: TList<TNeed>;
begin
  // Walk statt Rekursion.
  mNeeds := TList<TNeed>.Create;
  try
    ANode.Walk(
      function(AChild: TSyntaxNode): Boolean
      var
        Need: TNeed;
      begin
        Need.Node := AChild;
        Need.Names := nil;
        case AChild.Kind of
          TSyntaxKind.Identifier:
            if (AChild.Parent = nil) or (AChild.Parent.Kind <> TSyntaxKind.GenericParams) then
            begin
              Need.Names := [CleanName(AChild.Name)];
            end;
          TSyntaxKind.TypeReference:
            if AChild.Name <> '' then
            begin
              Need.Names := AChild.Name.Split(['.']);
            end;
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
        if Need.Names <> nil then
        begin
          mNeeds.Add(Need);
        end;
        Result := True;
      end);
    ANeeds := ANeeds + mNeeds.ToArray;
  finally
    mNeeds.Free;
  end;
end;

/// <summary>Namen aller uses-Einträge eines Abschnitts.</summary>
function SectionUses(ASection: TSyntaxNode): TArray<string>;
var
  mIndex, mItem: Integer;
begin
  Result := nil;
  if ASection = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to ASection.ChildCount - 1 do
  begin
    if ASection[mIndex].Kind = TSyntaxKind.UsesClause then
    begin
      for mItem := 0 to ASection[mIndex].ChildCount - 1 do
      begin
        AddUnique(Result, ASection[mIndex][mItem].Name);
      end;
    end;
  end;
end;

/// <summary>Schreibweise aus den uses der Ursprungs-Unit (SysUtils statt System.SysUtils), sonst AUnit.</summary>
function Spelling(const AOriginUses: TArray<string>; const AUnit: string): string;
var
  mItem: string;
begin
  for mItem in AOriginUses do
  begin
    if SameText(mItem, AUnit) or EndsText('.' + mItem, AUnit) then
    begin
      Exit(mItem);
    end;
  end;
  Result := AUnit;
end;

/// <summary>Reihenfolge wie in den uses der Ursprungs-Unit, fremde Units dahinter.</summary>
function Ordered(const AOriginUses, AUnits: TArray<string>): TArray<string>;
var
  mItem: string;
begin
  Result := nil;
  for mItem in AOriginUses do
  begin
    if Contains(AUnits, mItem) then
    begin
      Result := Result + [mItem];
    end;
  end;
  for mItem in AUnits do
  begin
    AddUnique(Result, mItem);
  end;
end;

function UsesText(const AUnits: TArray<string>; const ALineBreak: string): string;
begin
  Result := '';
  if AUnits = nil then
  begin
    Exit;
  end;
  Result := 'uses' + ALineBreak + '  ' + string.Join(',' + ALineBreak + '  ', AUnits) + ';' + ALineBreak +
    ALineBreak;
end;

/// <summary>Edit, das den Qualifizierer AOrigin vor dem Token an AIndex (Alt.TKunde) durch ANew ersetzt; False
/// ohne Qualifizierer.</summary>
function QualifierEdit(const ATokens: TArray<TPascalToken>; AIndex: Integer; const AOrigin, ANew: string;
  out AEdit: TTextEdit): Boolean;
var
  mParts: TArray<string>;
  mDot, mName, mPart, mBefore: Integer;
begin
  Result := False;
  mParts := AOrigin.Split(['.']);
  mDot := TRoutineBody.PreviousToken(ATokens, AIndex);
  if (mDot < 0) or not ATokens[mDot].IsSymbol('.') then
  begin
    Exit;
  end;
  mName := mDot;
  for mPart := High(mParts) downto 0 do
  begin
    if mPart < High(mParts) then
    begin
      mName := TRoutineBody.PreviousToken(ATokens, mName);
      if (mName < 0) or not ATokens[mName].IsSymbol('.') then
      begin
        Exit;
      end;
    end;
    mName := TRoutineBody.PreviousToken(ATokens, mName);
    if (mName < 0) or (ATokens[mName].Kind <> TPascalTokenKind.Identifier) or
      not SameText(CleanName(ATokens[mName].Text), mParts[mPart]) then
    begin
      Exit;
    end;
  end;
  // Steht davor ein weiterer Punkt, ist es ein Mitglied eines anderen Namens.
  mBefore := TRoutineBody.PreviousToken(ATokens, mName);
  if (mBefore >= 0) and ATokens[mBefore].IsSymbol('.') then
  begin
    Exit;
  end;
  AEdit := TTextEdit.Create(TTextRange.Create(ATokens[mName].StartPos, ATokens[mDot].StartPos), ANew);
  Result := True;
end;

function IsClassToken(const ATokens: TArray<TPascalToken>; AIndex: Integer; const AClassName: string): Boolean;
begin
  Result := (ATokens[AIndex].Kind = TPascalTokenKind.Identifier) and
    SameText(CleanName(ATokens[AIndex].Text), AClassName);
end;

/// <summary>Letzter Teil eines Namens mit Punkten (System.Classes → Classes).</summary>
function LastPart(const AName: string): string;
begin
  Result := AName.Substring(AName.LastIndexOf('.') + 1);
end;

function IsClassOrRecord(ADecl: TSyntaxNode): Boolean;
var
  mTypeNode: TSyntaxNode;
begin
  mTypeNode := TypeNodeOf(ADecl);
  Result := (mTypeNode <> nil) and (mTypeNode.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType]);
end;

function IsForward(ADecl: TSyntaxNode): Boolean;
var
  mTypeNode: TSyntaxNode;
begin
  mTypeNode := TypeNodeOf(ADecl);
  Result := (mTypeNode <> nil) and (mTypeNode.Kind = TSyntaxKind.ForwardType);
end;

procedure AddTypeDecls(ASection: TSyntaxNode; var AList: TArray<TSyntaxNode>);
var
  mItem, mInner: Integer;
begin
  for mItem := 0 to ASection.ChildCount - 1 do
  begin
    if ASection[mItem].Kind <> TSyntaxKind.TypeSection then
    begin
      Continue;
    end;
    for mInner := 0 to ASection[mItem].ChildCount - 1 do
    begin
      if ASection[mItem][mInner].Kind = TSyntaxKind.TypeDecl then
      begin
        AList := AList + [ASection[mItem][mInner]];
      end;
    end;
  end;
end;

/// <summary>Typdeklarationen aus interface und implementation in Quelltextreihenfolge.</summary>
function TypeDecls(ARoot: TSyntaxNode): TArray<TSyntaxNode>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ARoot.ChildCount - 1 do
  begin
    if IsSection(ARoot[mIndex]) then
    begin
      AddTypeDecls(ARoot[mIndex], Result);
    end;
  end;
end;

/// <summary>Bindet die Unit eine Formulardatei ein?</summary>
function HasFormResource(const AText: string): Boolean;
begin
  Result := ContainsText(AText, '{$R *.dfm}') or ContainsText(AText, '{$R *.fmx}') or
    ContainsText(AText, '{$R *.xfm}');
end;

function IsFormAncestor(const AAncestor: string): Boolean;
var
  mName: string;
begin
  mName := LastPart(AAncestor);
  Result := MatchText(mName, ['TForm', 'TFrame', 'TDataModule']) or EndsText('Form', mName) or
    EndsText('Frame', mName);
end;

/// <summary>Vorfahr einer Klasse wie geschrieben; '' ohne.</summary>
function AncestorName(ATypeNode: TSyntaxNode): string;
begin
  Result := '';
  if (ATypeNode.Kind = TSyntaxKind.ClassType) and (ATypeNode.ChildCount > 0) and
    (ATypeNode[0].Kind = TSyntaxKind.TypeReference) then
  begin
    Result := ATypeNode[0].Name;
  end;
end;

/// <summary>Attribute direkt vor ADecl im Typabschnitt.</summary>
function AttributesBefore(ATypeSection, ADecl: TSyntaxNode): TArray<TSyntaxNode>;
var
  mIndex, mItem: Integer;
begin
  Result := nil;
  mIndex := -1;
  for mItem := 0 to ATypeSection.ChildCount - 1 do
  begin
    if ATypeSection[mItem] = ADecl then
    begin
      mIndex := mItem;
    end;
  end;
  while (mIndex > 0) and (ATypeSection[mIndex - 1].Kind = TSyntaxKind.Attribute) do
  begin
    Dec(mIndex);
    Result := TArray<TSyntaxNode>.Create(ATypeSection[mIndex]) + Result;
  end;
end;

function MethodsOf(AImplementation: TSyntaxNode; const AClassName: string): TArray<TSyntaxNode>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AImplementation.ChildCount - 1 do
  begin
    if IsMethodOf(AImplementation[mIndex], AClassName) then
    begin
      Result := Result + [AImplementation[mIndex]];
    end;
  end;
end;

function NeedsOf(const ANodes: TArray<TSyntaxNode>): TArray<TNeed>;
var
  mNode: TSyntaxNode;
begin
  Result := nil;
  for mNode in ANodes do
  begin
    CollectNeeds(mNode, Result);
  end;
end;

procedure AddAll(var AList: TArray<string>; const ANames: TArray<string>);
var
  mName: string;
begin
  for mName in ANames do
  begin
    AddUnique(AList, mName);
  end;
end;

/// <summary>Namen aus ANames, die nicht in AExcluded stehen.</summary>
procedure AddMissing(var AList: TArray<string>; const ANames, AExcluded: TArray<string>);
var
  mName: string;
begin
  for mName in ANames do
  begin
    if not Contains(AExcluded, mName) then
    begin
      AddUnique(AList, mName);
    end;
  end;
end;

/// <summary>Insertion Sort nach Beginn; stabil bei gleichem Beginn.</summary>
procedure SortByStart(var ARanges: TArray<TOffsetRange>);
var
  mIndex, mItem: Integer;
  mPiece: TOffsetRange;
begin
  for mIndex := 1 to High(ARanges) do
  begin
    mPiece := ARanges[mIndex];
    mItem := mIndex - 1;
    while (mItem >= 0) and (ARanges[mItem].Start > mPiece.Start) do
    begin
      ARanges[mItem + 1] := ARanges[mItem];
      Dec(mItem);
    end;
    ARanges[mItem + 1] := mPiece;
  end;
end;

function RemovalEdit(const ALines: TLineTable; const ARange: TOffsetRange): TTextEdit;
begin
  Result := TTextEdit.Create(TTextRange.Create(ALines.PositionAt(ARange.Start), ALines.PositionAt(ARange.Stop)), '');
end;

/// <summary>Löschungen aus sortierten Bereichen; überlappende fasst es zusammen.</summary>
function MergedEdits(const ARanges: TArray<TOffsetRange>; const ALines: TLineTable): TArray<TTextEdit>;
var
  mPiece, mLast: TOffsetRange;
begin
  Result := nil;
  mLast := MakeRange(-1, -1);
  for mPiece in ARanges do
  begin
    if (mLast.Start >= 0) and (mPiece.Start <= mLast.Stop) then
    begin
      if mPiece.Stop > mLast.Stop then
      begin
        mLast.Stop := mPiece.Stop;
      end;
      Continue;
    end;
    if mLast.Start >= 0 then
    begin
      Result := Result + [RemovalEdit(ALines, mLast)];
    end;
    mLast := mPiece;
  end;
  if mLast.Start >= 0 then
  begin
    Result := Result + [RemovalEdit(ALines, mLast)];
  end;
end;

function ParsesCleanly(const AText: string): Boolean;
var
  mCheck: TSyntaxTree;
begin
  mCheck := TSyntaxTreeCache.Parse(AText);
  try
    Result := Length(mCheck.Diagnostics) = 0;
  finally
    mCheck.Free;
  end;
end;

function IsReferenced(const AReferences: TArray<TTextRange>; const APosition: TTextPosition): Boolean;
var
  mReference: TTextRange;
begin
  if AReferences = nil then
  begin
    Exit(True);
  end;
  for mReference in AReferences do
  begin
    if mReference.StartPos = APosition then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Qualifizierer der Klasse auf die neue Unit umstellen; AFirst: erste betroffene Stelle, -1 ohne.
/// </summary>
function QualifierEditsFor(const ATokens: TArray<TPascalToken>; const ANames: TMoveClassNames;
  const AReferences: TArray<TTextRange>; out AFirst: Integer): TArray<TTextEdit>;
var
  mIndex: Integer;
  mEdit: TTextEdit;
begin
  Result := nil;
  AFirst := -1;
  for mIndex := 0 to High(ATokens) do
  begin
    if not IsClassToken(ATokens, mIndex, ANames.ClassName) or
      not IsReferenced(AReferences, ATokens[mIndex].StartPos) then
    begin
      Continue;
    end;
    if AFirst < 0 then
    begin
      AFirst := mIndex;
    end;
    if QualifierEdit(ATokens, mIndex, ANames.OriginUnit, ANames.NewUnit, mEdit) then
    begin
      Result := Result + [mEdit];
    end;
  end;
end;

/// <summary>uses-Abschnitt, der die Ursprungs-Unit einbindet; mit Namespace-Präfix des Projekts steht
/// Firma.Lager als Lager darin.</summary>
function OriginUsesOffset(const ATokens: TArray<TPascalToken>; const AOriginUnit: string;
  out AOffset: Integer): Boolean;
var
  mClause: TUsesClauseInfo;
begin
  for mClause in TUsesClauses.Clauses(ATokens) do
  begin
    if Contains(mClause.Names, AOriginUnit) or Contains(mClause.Names, LastPart(AOriginUnit)) then
    begin
      AOffset := ATokens[mClause.UsesIndex].Offset;
      Exit(True);
    end;
  end;
  AOffset := -1;
  Result := False;
end;

/// <summary>Neue Unit neben die Ursprungs-Unit ins uses; nur über die Referenzsuche sicher auch ohne sie, dann
/// im Abschnitt der ersten Stelle.</summary>
procedure AddUserUses(const AText: string; ATree: TSyntaxTree; const ANewUnit, AOriginUnit: string;
  AFallback: Integer; var AEdits: TArray<TTextEdit>);
var
  mOffset: Integer;
  mFound: Boolean;
  mEdit: TTextEdit;
begin
  mFound := OriginUsesOffset(ATree.Tokens, AOriginUnit, mOffset);
  if not mFound and (AFallback >= 0) then
  begin
    mFound := True;
    mOffset := ATree.Tokens[AFallback].Offset;
  end;
  if mFound and TUsesClauses.AddUnit(ATree.Tokens, mOffset, ANewUnit, TTextLines.LineBreakOf(AText), mEdit) then
  begin
    AEdits := AEdits + [mEdit];
  end;
end;

type
  /// <summary>Arbeitsstand von TMoveClass.Plan; jeder Schritt liefert einen Grund oder ''.</summary>
  TMovePlanning = record
    Source: TMoveClassSource;
    Lookup: TMoveClassLookup;
    Lines: TLineTable;
    LineBreak: string;
    Decl: TSyntaxNode;
    TypeNode: TSyntaxNode;
    TypeSection: TSyntaxNode;
    Section: TSyntaxNode;
    InterfaceNode: TSyntaxNode;
    ImplementationNode: TSyntaxNode;
    Forwards: TArray<TSyntaxNode>;
    Attributes: TArray<TSyntaxNode>;
    Methods: TArray<TSyntaxNode>;
    DeclRange: TOffsetRange;
    /// <summary>Typkommentar über den Rümpfen (#1838); Start = Stop ohne.</summary>
    HeaderRange: TOffsetRange;
    Moved: TArray<TOffsetRange>;
    TopLevel: TDictionary<string, Integer>;
    Own: TDictionary<string, Boolean>;
    OriginUses: TArray<string>;
    DeclUnits: TArray<string>;
    BodyUnits: TArray<string>;
    DeclNeedsOrigin: Boolean;
    BodyNeedsOrigin: Boolean;
    UnknownInDecl: Boolean;
    UnknownInBody: Boolean;
    InterfaceRef: Boolean;
    ImplementationRef: Boolean;
    Plan: TMoveClassPlan;
    class function Create(const ASource: TMoveClassSource; const ALookup: TMoveClassLookup): TMovePlanning; static;
    function Start(const APosition: TTextPosition; const ANewUnit: string): string;
    function NamesIssue: string;
    function ForwardsIssue: string;
    function FormIssue: string;
    function PieceOf(ANode: TSyntaxNode): TOffsetRange;
    procedure CollectPieces;
    function ConditionalIssue: string;
    procedure CollectNames;
    function ResolveIssue: string;
    function NeedsIssue(const ANeeds: TArray<TNeed>; AInDecl: Boolean): string;
    function LookupMeaning(const ANeed: TNeed): TMoveClassMeaning;
    function ResolveLocally(const ANeed: TNeed; AInDecl: Boolean; var AMeaning: TMoveClassMeaning): Boolean;
    procedure MarkUnknown(const ANeed: TNeed; AInDecl: Boolean);
    function IsOrigin(const AMeaning: TMoveClassMeaning): Boolean;
    function OriginNeedIssue(const AMeaning: TMoveClassMeaning; const AName: string; AInDecl: Boolean): string;
    function NeedIssue(const ANeed: TNeed; AInDecl: Boolean): string;
    function IsRemainingUse(AIndex: Integer): Boolean;
    procedure CollectReferences;
    function CircularIssue: string;
    function InterfaceUsesOfNew: TArray<string>;
    function ImplementationUsesOfNew(const AInterfaceUses: TArray<string>): TArray<string>;
    function MethodsText: string;
    procedure BuildNewUnit;
    function CoversTypeSection: Boolean;
    function InsideTypeSection(const APiece: TOffsetRange): Boolean;
    function RemovalPieces: TArray<TOffsetRange>;
    function RemovalEdits: TArray<TTextEdit>;
    function QualifierEdits: TArray<TTextEdit>;
    function OriginEditsIssue: string;
    function ParseIssue: string;
  end;

class function TMovePlanning.Create(const ASource: TMoveClassSource; const ALookup: TMoveClassLookup): TMovePlanning;
begin
  Result := Default(TMovePlanning);
  Result.Source := ASource;
  Result.Lookup := ALookup;
end;

function TMovePlanning.Start(const APosition: TTextPosition; const ANewUnit: string): string;
begin
  Decl := TMoveClass.ClassAt(Source.Tree, APosition);
  if Decl = nil then
  begin
    Exit(cTexts[TEditingMoveClassText.NoClassAtThisPosition].Text);
  end;
  TypeNode := TypeNodeOf(Decl);
  TypeSection := Decl.Parent;
  Section := TypeSection.Parent;
  Plan.ClassName := CleanName(Decl.Name);
  Plan.OriginUnit := Source.Tree.Root.Name;
  Plan.NewUnit := Trim(ANewUnit);
  InterfaceNode := Source.Tree.Root.FindChild(TSyntaxKind.InterfaceSection);
  ImplementationNode := Source.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
  Lines := TLineTable.Build(Source.Text);
  LineBreak := TTextLines.LineBreakOf(Source.Text);
  Result := NamesIssue;
end;

function TMovePlanning.NamesIssue: string;
begin
  Result := '';
  if not IsValidIdent(Plan.NewUnit, True) then
  begin
    Result := cTexts[TEditingMoveClassText.IsNotAValidUnit].Fmt([Plan.NewUnit]);
  end
  else if SameText(Plan.NewUnit, Plan.OriginUnit) then
  begin
    Result := cTexts[TEditingMoveClassText.TheNewUnitWouldHave].Text;
  end
  else if (InterfaceNode = nil) or (ImplementationNode = nil) then
  begin
    Result := cTexts[TEditingMoveClassText.TheUnitHasNoInterface].Text;
  end;
end;

/// <summary>Gleichnamige Typen verhindern das Verschieben; Vorwärtsdeklarationen wandern mit.</summary>
function TMovePlanning.ForwardsIssue: string;
var
  mNode: TSyntaxNode;
begin
  Result := '';
  Forwards := nil;
  for mNode in TypeDecls(Source.Tree.Root) do
  begin
    if (mNode = Decl) or not SameText(CleanName(mNode.Name), Plan.ClassName) then
    begin
      Continue;
    end;
    if not IsForward(mNode) then
    begin
      Exit(cTexts[TEditingMoveClassText.SeveralTypesAreNamed].Fmt([Plan.ClassName]));
    end;
    Forwards := Forwards + [mNode];
  end;
end;

/// <summary>Formularklassen bleiben bei ihrer .dfm bzw. .fmx.</summary>
function TMovePlanning.FormIssue: string;
var
  mAncestor: string;
begin
  Result := '';
  mAncestor := AncestorName(TypeNode);
  if (mAncestor <> '') and HasFormResource(Source.Text) and IsFormAncestor(mAncestor) then
  begin
    Result := cTexts[TEditingMoveClassText.FormClassesStayWithTheir].Text;
  end;
end;

function TMovePlanning.PieceOf(ANode: TSyntaxNode): TOffsetRange;
begin
  Result := MakeRange(WithLeadingComments(Source.Text, Lines, Source.Tree.Tokens, ANode.StartOffset),
    ANode.EndOffset);
end;

/// <summary>Verschobene Stücke: Deklaration samt Attributen und Kommentar, Vorwärtsdeklarationen, Methoden.</summary>
procedure TMovePlanning.CollectPieces;
var
  mNode: TSyntaxNode;
begin
  Attributes := AttributesBefore(TypeSection, Decl);
  DeclRange := MakeRange(Decl.StartOffset, Decl.EndOffset);
  if Attributes <> nil then
  begin
    DeclRange.Start := Attributes[0].StartOffset;
  end;
  DeclRange.Start := WithLeadingComments(Source.Text, Lines, Source.Tree.Tokens, DeclRange.Start);
  Methods := MethodsOf(ImplementationNode, Plan.ClassName);
  Moved := [DeclRange];
  for mNode in Forwards do
  begin
    Moved := Moved + [PieceOf(mNode)];
  end;
  for mNode in Methods do
  begin
    Moved := Moved + [PieceOf(mNode)];
  end;
  HeaderRange := MakeRange(0, 0);
  if Methods <> nil then
  begin
    HeaderRange := TypeHeaderRange(Source, Lines, Lines.PositionAt(PieceOf(Methods[0]).Start).Line, Plan.ClassName);
  end;
  if HeaderRange.Stop > HeaderRange.Start then
  begin
    Moved := Moved + [HeaderRange];
  end;
end;

function TMovePlanning.ConditionalIssue: string;
var
  mPiece: TOffsetRange;
begin
  Result := '';
  for mPiece in Moved do
  begin
    if not Unconditional(Source.Tree.Tokens, mPiece) then
    begin
      Exit(cTexts[TEditingMoveClassText.PartOfTheClassIs].Text);
    end;
  end;
end;

/// <summary>Namen der Ursprungs-Unit und die eigenen Namen der Klasse.</summary>
procedure TMovePlanning.CollectNames;
var
  mNode: TSyntaxNode;
begin
  CollectTopLevel(InterfaceNode, TopLevel);
  CollectTopLevel(ImplementationNode, TopLevel);
  CollectOwnNames(Decl, Own);
  for mNode in Methods do
  begin
    CollectOwnNames(mNode, Own);
  end;
  Own.AddOrSetValue('result', True);
  Own.AddOrSetValue('self', True);
  OriginUses := SectionUses(InterfaceNode) + SectionUses(ImplementationNode);
end;

/// <summary>Benötigte Namen der Deklaration und der Rümpfe den uses zuordnen.</summary>
function TMovePlanning.ResolveIssue: string;
begin
  TopLevel := TDictionary<string, Integer>.Create;
  Own := TDictionary<string, Boolean>.Create;
  try
    CollectNames;
    Result := NeedsIssue(NeedsOf(TArray<TSyntaxNode>.Create(Decl) + Attributes), True);
    if Result = '' then
    begin
      Result := NeedsIssue(NeedsOf(Methods), False);
    end;
  finally
    Own.Free;
    TopLevel.Free;
    Own := nil;
    TopLevel := nil;
  end;
end;

function TMovePlanning.NeedsIssue(const ANeeds: TArray<TNeed>; AInDecl: Boolean): string;
var
  mNeed: TNeed;
begin
  Result := '';
  for mNeed in ANeeds do
  begin
    Result := NeedIssue(mNeed, AInDecl);
    if Result <> '' then
    begin
      Exit;
    end;
  end;
end;

/// <summary>Bedeutung über die Namensauflösung; Attribute: [Weak] meint WeakAttribute.</summary>
function TMovePlanning.LookupMeaning(const ANeed: TNeed): TMoveClassMeaning;
begin
  Result := Default(TMoveClassMeaning);
  if not Assigned(Lookup) then
  begin
    Exit;
  end;
  Result := Lookup(Source.Tree, Source.FileName, ANeed.Names, ANeed.Node.StartOffset);
  if not Result.Found and IsAttributeName(ANeed.Node) then
  begin
    Result := Lookup(Source.Tree, Source.FileName, TArray<string>.Create(ANeed.Names[0] + 'Attribute'),
      ANeed.Node.StartOffset);
  end;
end;

/// <summary>Ohne Namensauflösung: eigene Namen, dann die der Ursprungs-Unit. True mit Bedeutung in AMeaning;
/// False, wenn der Name nichts braucht oder unbekannt bleibt.</summary>
function TMovePlanning.ResolveLocally(const ANeed: TNeed; AInDecl: Boolean;
  var AMeaning: TMoveClassMeaning): Boolean;
var
  mName: string;
  mOffset: Integer;
begin
  Result := False;
  mName := ANeed.Names[0];
  if (Length(ANeed.Names) = 1) and (Own.ContainsKey(LowerCase(mName)) or MatchText(mName, cSystemNames)) then
  begin
    Exit;
  end;
  if TopLevel.TryGetValue(LowerCase(mName), mOffset) then
  begin
    AMeaning.Found := True;
    AMeaning.UnitName := Plan.OriginUnit;
    AMeaning.FileName := Source.FileName;
    AMeaning.Position := Lines.PositionAt(mOffset);
    Exit(True);
  end;
  if not SameText(mName, Plan.OriginUnit) then
  begin
    MarkUnknown(ANeed, AInDecl);
  end;
end;

procedure TMovePlanning.MarkUnknown(const ANeed: TNeed; AInDecl: Boolean);
begin
  AddUnique(Plan.Unresolved, string.Join('.', ANeed.Names));
  if AInDecl then
  begin
    UnknownInDecl := True;
  end
  else
  begin
    UnknownInBody := True;
  end;
end;

function TMovePlanning.IsOrigin(const AMeaning: TMoveClassMeaning): Boolean;
begin
  Result := SameText(AMeaning.UnitName, Plan.OriginUnit) or
    ((AMeaning.FileName <> '') and SameText(AMeaning.FileName, Source.FileName));
end;

/// <summary>Name aus der Ursprungs-Unit: verschoben, aus deren interface oder (nicht erreichbar) aus deren
/// implementation.</summary>
function TMovePlanning.OriginNeedIssue(const AMeaning: TMoveClassMeaning; const AName: string;
  AInDecl: Boolean): string;
var
  mOffset: Integer;
begin
  Result := '';
  mOffset := Lines.OffsetAt(AMeaning.Position);
  if InRanges(Moved, mOffset) then
  begin
    Exit;
  end;
  if mOffset >= ImplementationNode.StartOffset then
  begin
    Exit(cTexts[TEditingMoveClassText.TheClassUsesFromThe].Fmt([AName, Plan.OriginUnit]));
  end;
  if AInDecl then
  begin
    DeclNeedsOrigin := True;
  end
  else
  begin
    BodyNeedsOrigin := True;
  end;
end;

function TMovePlanning.NeedIssue(const ANeed: TNeed; AInDecl: Boolean): string;
var
  mMeaning: TMoveClassMeaning;
begin
  Result := '';
  mMeaning := LookupMeaning(ANeed);
  if not mMeaning.Found and not ResolveLocally(ANeed, AInDecl, mMeaning) then
  begin
    Exit;
  end;
  if mMeaning.IsLocal or (mMeaning.UnitName = '') or MatchText(mMeaning.UnitName, ['System', 'SysInit']) then
  begin
    Exit;
  end;
  if IsOrigin(mMeaning) then
  begin
    Exit(OriginNeedIssue(mMeaning, ANeed.Names[0], AInDecl));
  end;
  if AInDecl then
  begin
    AddUnique(DeclUnits, Spelling(OriginUses, mMeaning.UnitName));
  end
  else
  begin
    AddUnique(BodyUnits, Spelling(OriginUses, mMeaning.UnitName));
  end;
end;

/// <summary>Verwendung der Klasse, die in der Ursprungs-Unit bleibt.</summary>
function TMovePlanning.IsRemainingUse(AIndex: Integer): Boolean;
begin
  Result := IsClassToken(Source.Tree.Tokens, AIndex, Plan.ClassName) and
    not InRanges(Moved, Source.Tree.Tokens[AIndex].Offset);
end;

/// <summary>Verwendet die Ursprungs-Unit die Klasse noch, im interface bzw. im implementation?</summary>
procedure TMovePlanning.CollectReferences;
var
  mIndex, mOffset: Integer;
begin
  InterfaceRef := False;
  ImplementationRef := False;
  for mIndex := Source.Tree.FirstTokenFrom(InterfaceNode.StartOffset) to High(Source.Tree.Tokens) do
  begin
    mOffset := Source.Tree.Tokens[mIndex].Offset;
    if not IsRemainingUse(mIndex) or (mOffset < InterfaceNode.StartOffset) then
    begin
      Continue;
    end;
    if mOffset < ImplementationNode.StartOffset then
    begin
      InterfaceRef := True;
    end
    else
    begin
      ImplementationRef := True;
    end;
  end;
end;

function TMovePlanning.CircularIssue: string;
begin
  Result := '';
  CollectReferences;
  if DeclNeedsOrigin and InterfaceRef then
  begin
    Result := cTexts[TEditingMoveClassText.CircularReferenceTheClassNeeds].Fmt([Plan.OriginUnit]);
  end;
end;

function TMovePlanning.InterfaceUsesOfNew: TArray<string>;
begin
  Result := DeclUnits;
  if UnknownInDecl then
  begin
    AddAll(Result, SectionUses(InterfaceNode));
    if Section = ImplementationNode then
    begin
      AddAll(Result, SectionUses(ImplementationNode));
    end;
  end;
  Result := Ordered(OriginUses, Result);
  if DeclNeedsOrigin then
  begin
    Result := Result + [Plan.OriginUnit];
  end;
end;

function TMovePlanning.ImplementationUsesOfNew(const AInterfaceUses: TArray<string>): TArray<string>;
begin
  Result := nil;
  AddMissing(Result, BodyUnits, AInterfaceUses);
  if UnknownInBody then
  begin
    AddMissing(Result, OriginUses, AInterfaceUses);
  end;
  Result := Ordered(OriginUses, Result);
  if BodyNeedsOrigin and not DeclNeedsOrigin then
  begin
    Result := Result + [Plan.OriginUnit];
  end;
end;

function TMovePlanning.MethodsText: string;
var
  mNode: TSyntaxNode;
begin
  Result := '';
  if HeaderRange.Stop > HeaderRange.Start then
  begin
    Result := PieceText(Source.Text, Lines, HeaderRange);
  end;
  for mNode in Methods do
  begin
    if Result <> '' then
    begin
      Result := Result + LineBreak + LineBreak;
    end;
    Result := Result + PieceText(Source.Text, Lines, PieceOf(mNode));
  end;
  if Result <> '' then
  begin
    Result := Result + LineBreak + LineBreak;
  end;
end;

procedure TMovePlanning.BuildNewUnit;
var
  mInterfaceUses, mImplementationUses: TArray<string>;
begin
  mInterfaceUses := InterfaceUsesOfNew;
  mImplementationUses := ImplementationUsesOfNew(mInterfaceUses);
  Plan.UsesOrigin := DeclNeedsOrigin or BodyNeedsOrigin;
  Plan.Text := 'unit ' + Plan.NewUnit + ';' + LineBreak + LineBreak + 'interface' + LineBreak + LineBreak +
    UsesText(mInterfaceUses, LineBreak) + 'type' + LineBreak + PieceText(Source.Text, Lines, DeclRange) + LineBreak +
    LineBreak + 'implementation' + LineBreak + LineBreak + UsesText(mImplementationUses, LineBreak) + MethodsText +
    'end.' + LineBreak;
end;

/// <summary>Wird der Typabschnitt durch das Verschieben leer?</summary>
function TMovePlanning.CoversTypeSection: Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to TypeSection.ChildCount - 1 do
  begin
    if not InRanges(Moved, TypeSection[mIndex].StartOffset) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

function TMovePlanning.InsideTypeSection(const APiece: TOffsetRange): Boolean;
begin
  Result := (APiece.Start >= TypeSection.StartOffset) and (APiece.Stop <= TypeSection.EndOffset);
end;

/// <summary>Zu entfernende Stücke; ein Typabschnitt, der leer würde, entfällt ganz.</summary>
function TMovePlanning.RemovalPieces: TArray<TOffsetRange>;
var
  mWhole: Boolean;
  mPiece: TOffsetRange;
begin
  Result := nil;
  mWhole := CoversTypeSection;
  if mWhole then
  begin
    Result := [PieceOf(TypeSection)];
  end;
  for mPiece in Moved do
  begin
    if not (mWhole and InsideTypeSection(mPiece)) then
    begin
      Result := Result + [mPiece];
    end;
  end;
end;

function TMovePlanning.RemovalEdits: TArray<TTextEdit>;
var
  mRemovals: TArray<TOffsetRange>;
  mIndex: Integer;
begin
  mRemovals := RemovalPieces;
  for mIndex := 0 to High(mRemovals) do
  begin
    mRemovals[mIndex] := RemovalRange(Source.Text, Lines, mRemovals[mIndex]);
  end;
  SortByStart(mRemovals);
  Result := MergedEdits(mRemovals, Lines);
end;

/// <summary>Qualifizierte Verwendungen (Alt.TKunde), die in der Ursprungs-Unit bleiben.</summary>
function TMovePlanning.QualifierEdits: TArray<TTextEdit>;
var
  mIndex: Integer;
  mEdit: TTextEdit;
begin
  Result := nil;
  for mIndex := 0 to High(Source.Tree.Tokens) do
  begin
    if IsRemainingUse(mIndex) and QualifierEdit(Source.Tree.Tokens, mIndex, Plan.OriginUnit, Plan.NewUnit,
      mEdit) then
    begin
      Result := Result + [mEdit];
    end;
  end;
end;

/// <summary>Änderungen der Ursprungs-Unit; sie bindet die neue Unit ein, wo sie die Klasse noch verwendet.
/// </summary>
function TMovePlanning.OriginEditsIssue: string;
var
  mEdits: TArray<TTextEdit>;
  mEdit: TTextEdit;
  mOffset: Integer;
begin
  Result := '';
  mEdits := RemovalEdits;
  if InterfaceRef or ImplementationRef then
  begin
    mOffset := ImplementationNode.StartOffset;
    if InterfaceRef then
    begin
      mOffset := InterfaceNode.StartOffset;
    end;
    if not TUsesClauses.AddUnit(Source.Tree.Tokens, mOffset, Plan.NewUnit, LineBreak, mEdit) then
    begin
      Exit(cTexts[TEditingMoveClassText.NoRoomForTheNew].Text);
    end;
    mEdits := mEdits + [mEdit];
  end;
  Plan.OriginEdits := mEdits + QualifierEdits;
end;

/// <summary>Vorher fehlerfrei, nachher auch.</summary>
function TMovePlanning.ParseIssue: string;
begin
  Result := '';
  if Length(Source.Tree.Diagnostics) > 0 then
  begin
    Exit;
  end;
  if not ParsesCleanly(TChangeSignature.ApplyEdits(Source.Text, Plan.OriginEdits)) then
  begin
    Result := cTexts[TEditingMoveClassText.TheOriginalUnitNoLonger].Text;
  end
  else if not ParsesCleanly(Plan.Text) then
  begin
    Result := cTexts[TEditingMoveClassText.TheNewUnitDoesNot].Text;
  end;
end;

{ TMoveClassSource }

class function TMoveClassSource.Create(const AFileName, AText: string; ATree: TSyntaxTree): TMoveClassSource;
begin
  Result.FileName := AFileName;
  Result.Text := AText;
  Result.Tree := ATree;
  Result.TypeComments := True;
end;

{ TMoveClassNames }

class function TMoveClassNames.Create(const AOriginUnit, ANewUnit, AClassName: string): TMoveClassNames;
begin
  Result.OriginUnit := AOriginUnit;
  Result.NewUnit := ANewUnit;
  Result.ClassName := AClassName;
end;

{ TMoveClassPlan }

function TMoveClassPlan.Names: TMoveClassNames;
begin
  Result := TMoveClassNames.Create(OriginUnit, NewUnit, ClassName);
end;

{ TMoveClass }

class function TMoveClass.ClassAt(ATree: TSyntaxTree; const APosition: TTextPosition): TSyntaxNode;
var
  mDecl: TSyntaxNode;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) or (ATree.Root.Kind <> TSyntaxKind.UnitFile) then
  begin
    Exit;
  end;
  for mDecl in TypeDecls(ATree.Root) do
  begin
    if (mDecl.StartPos.Line = APosition.Line) and IsClassOrRecord(mDecl) then
    begin
      Exit(mDecl);
    end;
  end;
end;

class function TMoveClass.DefaultUnitName(const AClassName: string): string;
begin
  Result := AClassName;
  if (Length(Result) > 1) and CharInSet(Result[1], ['T', 't']) and CharInSet(Result[2], ['A'..'Z']) then
  begin
    Result := Result.Substring(1);
  end;
end;

class function TMoveClass.Plan(const ASource: TMoveClassSource; const APosition: TTextPosition;
  const ANewUnit: string; const ALookup: TMoveClassLookup; out APlan: TMoveClassPlan; out AReason: string): Boolean;
var
  mPlanning: TMovePlanning;
begin
  mPlanning := TMovePlanning.Create(ASource, ALookup);
  AReason := mPlanning.Start(APosition, ANewUnit);
  if AReason = '' then
  begin
    AReason := mPlanning.ForwardsIssue;
  end;
  if AReason = '' then
  begin
    AReason := mPlanning.FormIssue;
  end;
  if AReason = '' then
  begin
    mPlanning.CollectPieces;
    AReason := mPlanning.ConditionalIssue;
  end;
  if AReason = '' then
  begin
    AReason := mPlanning.ResolveIssue;
  end;
  if AReason = '' then
  begin
    AReason := mPlanning.CircularIssue;
  end;
  if AReason = '' then
  begin
    mPlanning.BuildNewUnit;
    AReason := mPlanning.OriginEditsIssue;
  end;
  if AReason = '' then
  begin
    AReason := mPlanning.ParseIssue;
  end;
  APlan := mPlanning.Plan;
  Result := AReason = '';
end;

class function TMoveClass.UpdateUser(const AText: string; ATree: TSyntaxTree; const ANames: TMoveClassNames;
  const AReferences: TArray<TTextRange>; AAddUses: Boolean; out AEdits: TArray<TTextEdit>): Boolean;
var
  mFirst, mFallback: Integer;
begin
  AEdits := QualifierEditsFor(ATree.Tokens, ANames, AReferences, mFirst);
  if mFirst < 0 then
  begin
    Exit(False);
  end;
  if AAddUses and not Contains(TUsesClauses.UsedUnits(ATree.Tokens), ANames.NewUnit) then
  begin
    mFallback := -1;
    if AReferences <> nil then
    begin
      mFallback := mFirst;
    end;
    AddUserUses(AText, ATree, ANames.NewUnit, ANames.OriginUnit, mFallback, AEdits);
  end;
  Result := AEdits <> nil;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.MoveClass', cTexts);

end.
