unit Atlas.Common.Rules.Builtin.Testing.TestCaseTable;

// [TestCase]-Attribute einer Testmethode als Tabelle (#1879): lesen und zurückschreiben.
//   - Lesen: Je Testmethode mit [TestCase] eine Tabelle mit einer Spalte je Parameter (Name, Typ, Art wie
//     dunitx-testcase-mismatch) und einer Zeile je Fall (Name, Werte, Trennzeichen, Form). Werte und Trennzeichen
//     liest TDUnitXTestCases.Read wie die Regel, die Prüfung einer Zelle ist dieselbe wie dort (Fits).
//   - Schreiben: Die Zeilen werden als je ein Attribut in einer eigenen Zeile mit der Einrückung des ersten
//     [TestCase] geschrieben; ein Edit ersetzt alles vom ersten bis zum letzten [TestCase]-Attribut (ein
//     Rückgängig-Schritt im Editor). Jede Zeile behält Form (TestCase('Name', 'Werte'), TestCase('Werte'),
//     NamedTestCase), Attributnamen, Trennzeichen und weitere Argumente (Trim); neue Zeilen übernehmen sie von
//     der letzten Zeile.
//   - Bearbeitbar ist die Tabelle nur, wenn jedes [TestCase] allein in seinen Klammern steht, die Attribute
//     lesbar sind (Literale) und zwischen ihnen nur Leerraum und andere ganze Attribute stehen; andere Attribute
//     dazwischen ([Test], [Category]) wandern beim Schreiben vor die Fälle. Sonst nennt Reason den Grund.
// DUnitX kennt in den Werten keine Anführung: Ein Wert mit einem Zeichen des Trennzeichens ist ein Fehler der
// Zelle und lässt sich nicht schreiben.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Builtin.Testing.TestCases;

type
{$SCOPEDENUMS ON}
  /// <summary>Schreibweise eines Falls: TestCase('Name', 'Werte'), TestCase('Werte'), NamedTestCase(…).</summary>
  TTestCaseForm = (Classic, ValuesOnly, Named);
{$SCOPEDENUMS OFF}

  /// <summary>Eine Spalte: ein Parameter der Testmethode.</summary>
  TTestCaseColumn = record
    Name: string;
    /// <summary>Typ wie geschrieben; '' ohne Typ.</summary>
    TypeName: string;
    Kind: TDUnitXValueKind;
    /// <summary>Namen der Aufzählung ("Rot,Gruen"); '' bei anderen Typen.</summary>
    EnumNames: string;
  end;

  /// <summary>Eine Zeile: ein [TestCase].</summary>
  TTestCaseRow = record
    /// <summary>Name des Falls; '' bei TestCase('Werte').</summary>
    Name: string;
    Values: TArray<string>;
    /// <summary>Trennzeichen der Werte (Vorgabe Komma).</summary>
    Separator: string;
    Form: TTestCaseForm;
    /// <summary>Attributname wie geschrieben (TestCase, TestCaseAttribute, DUnitX.TestFramework.TestCase).</summary>
    AttributeName: string;
    /// <summary>Weitere Argumente hinter dem Trennzeichen wie geschrieben (", True"); '' ohne.</summary>
    Tail: string;
    /// <summary>Steht das Trennzeichen als Argument da?</summary>
    HasSeparator: Boolean;
    /// <summary>Zeile des Attributs (0-basiert); -1 bei neuen Zeilen.</summary>
    Line: Integer;
  end;

  /// <summary>Die Fälle einer Testmethode.</summary>
  TTestCaseTable = record
    /// <summary>Klasse der Methode.</summary>
    Fixture: string;
    Method: string;
    /// <summary>Zeile der Methodendeklaration (0-basiert).</summary>
    MethodLine: Integer;
    /// <summary>Erste Zeile des ersten Attributs vor der Methode.</summary>
    FirstLine: Integer;
    Columns: TArray<TTestCaseColumn>;
    Rows: TArray<TTestCaseRow>;
    /// <summary>Vom ersten bis zum Ende des letzten [TestCase]-Attributs (mit Klammern).</summary>
    Range: TTextRange;
    /// <summary>Einrückung des ersten [TestCase].</summary>
    Indent: string;
    /// <summary>Attribute zwischen den Fällen ([Test], [Category('x')]); sie stehen beim Schreiben davor.</summary>
    Between: TArray<string>;
    Editable: Boolean;
    /// <summary>Warum die Tabelle nicht bearbeitbar ist; sonst ''.</summary>
    Reason: string;
    /// <summary>Zahl der Fälle.</summary>
    function Count: Integer;
  end;

  TTestCaseTables = class
  public
    /// <summary>Alle Testmethoden mit [TestCase] in ATree (Text AText), in der Reihenfolge der Datei. Ohne
    /// Testunit (uses DUnitX.TestFramework …) leer.</summary>
    class function All(ATree: TSyntaxTree; const AText: string): TArray<TTestCaseTable>; static;
    /// <summary>Tabelle der Methode, zu der ALine gehört (Attribute bis Deklaration); False ohne.</summary>
    class function Find(ATree: TSyntaxTree; const AText: string; ALine: Integer;
      out ATable: TTestCaseTable): Boolean; static;
    /// <summary>Fehler der Zelle AValue in Spalte AColumn mit Trennzeichen ASeparator; '' passt.</summary>
    class function CellProblem(const AColumn: TTestCaseColumn; const AValue, ASeparator: string): string; static;
    /// <summary>Fehler der Zeile (Zahl der Werte, Methode ohne Parameter); '' passt.</summary>
    class function RowProblem(const ATable: TTestCaseTable; const ARow: TTestCaseRow): string; static;
    /// <summary>Neue Zeile mit Form, Trennzeichen und Argumenten wie die letzte von ATable.</summary>
    class function NewRow(const ATable: TTestCaseTable; const AName: string;
      const AValues: TArray<string>): TTestCaseRow; static;
    /// <summary>Das Attribut einer Zeile: [TestCase('A', '1,2')].</summary>
    class function AttributeText(const ARow: TTestCaseRow): string; static;
    /// <summary>Edit, das die Fälle von ATable durch ARows ersetzt; ALineEnd trennt die Zeilen. False mit
    /// AReason, wenn ATable nicht bearbeitbar ist, ARows leer ist oder ein Wert das Trennzeichen enthält.
    /// </summary>
    class function Write(const ATable: TTestCaseTable; const ARows: TArray<TTestCaseRow>; const ALineEnd: string;
      out AEdit: TTextEdit; out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.StringLiterals,
  Atlas.Common.Rules.Builtin.Testing.Classes,
  Atlas.Common.Localization.Texts,
  Atlas.Text.Lines;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TTestCaseTableText = (NotLiteral, SharedBrackets, CodeBetween, NoRows, ValueHasSeparator, NotInteger, NotFloat,
    NotBoolean, NotEnum, CountMismatch, NoParameters);

const
  cTexts: array[TTestCaseTableText] of TAtlasText = (
    (De: '%s enthält Werte, die keine String-Literale sind'; En: '%s contains values that are not string literals'),
    (De: '%s steht mit anderen Attributen in einer Klammer'; En: '%s shares its brackets with other attributes'),
    (De: 'Zwischen den TestCase-Attributen steht Text, der kein Attribut ist (Kommentar, Direktive)';
     En: 'There is text between the TestCase attributes that is not an attribute (comment, directive)'),
    (De: 'Mindestens ein Fall muss bleiben'; En: 'At least one case must remain'),
    (De: 'Wert enthält das Trennzeichen ''%s''; DUnitX kann ihn nicht übergeben';
     En: 'Value contains the separator ''%s''; DUnitX cannot pass it'),
    (De: 'Keine Ganzzahl (%s)'; En: 'Not an integer (%s)'),
    (De: 'Keine Zahl (%s)'; En: 'Not a number (%s)'),
    (De: 'Nur True oder False (%s)'; En: 'Only True or False (%s)'),
    (De: 'Kein Wert von %s (erlaubt: %s)'; En: 'Not a value of %s (allowed: %s)'),
    (De: '%d Werte, %s erwartet %d Parameter'; En: '%d values, %s expects %d parameters'),
    (De: '%s hat keine Parameter'; En: '%s has no parameters'));

{$SCOPEDENUMS OFF}

{ TTestCaseTable }

function TTestCaseTable.Count: Integer;
begin
  Result := Length(Rows);
end;

{ Lesen }

/// <summary>Quelltext eines Knotens.</summary>
function SourceOf(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

/// <summary>Spalten aus den Parametern der Methode AHeader.</summary>
function ColumnsOf(AHeader: TSyntaxNode; const AEnums: TArray<string>): TArray<TTestCaseColumn>;
var
  mParams: TArray<TDUnitXParameter>;
  mIndex: Integer;
begin
  mParams := TDUnitXTestCases.Parameters(AHeader);
  Result := nil;
  SetLength(Result, Length(mParams));
  for mIndex := 0 to High(mParams) do
  begin
    Result[mIndex].Name := mParams[mIndex].Name;
    Result[mIndex].TypeName := mParams[mIndex].TypeName;
    Result[mIndex].Kind := TDUnitXTestCases.KindOf(mParams[mIndex].TypeName, AEnums);
    Result[mIndex].EnumNames := TDUnitXTestCases.EnumNames(mParams[mIndex].TypeName, AEnums);
  end;
end;

/// <summary>Form, Name des Attributs, Trennzeichen-Argument und Rest einer gelesenen Zeile.</summary>
procedure ReadShape(const AText: string; const ACase: TDUnitXTestCase; var ARow: TTestCaseRow);
var
  mArgs: TArray<TSyntaxNode>;
  mIndex: Integer;
begin
  mArgs := TDUnitXClasses.Arguments(ACase.Item);
  ARow.AttributeName := SourceOf(AText, ACase.Item[0]);
  if SameText(TDUnitXClasses.ItemName(ACase.Item), 'NamedTestCase') then
  begin
    ARow.Form := TTestCaseForm.Named;
  end
  else if ACase.ValuesAt = 0 then
  begin
    ARow.Form := TTestCaseForm.ValuesOnly;
  end
  else
  begin
    ARow.Form := TTestCaseForm.Classic;
  end;
  ARow.HasSeparator := Length(mArgs) > ACase.ValuesAt + 1;
  ARow.Tail := '';
  for mIndex := ACase.ValuesAt + 2 to High(mArgs) do
  begin
    ARow.Tail := ARow.Tail + ', ' + SourceOf(AText, mArgs[mIndex]);
  end;
end;

/// <summary>Index von AHeader unter seinem Elternknoten; -1 ohne.</summary>
function IndexInParent(AHeader: TSyntaxNode): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to AHeader.Parent.ChildCount - 1 do
  begin
    if AHeader.Parent[mIndex] = AHeader then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Attribut-Knoten ([…]) direkt vor AHeader, in Reihenfolge der Datei.</summary>
function AttributesBefore(AHeader: TSyntaxNode): TArray<TSyntaxNode>;
var
  mIndex: Integer;
begin
  Result := nil;
  mIndex := IndexInParent(AHeader) - 1;
  while (mIndex >= 0) and (AHeader.Parent[mIndex].Kind = TSyntaxKind.Attribute) do
  begin
    Result := [AHeader.Parent[mIndex]] + Result;
    Dec(mIndex);
  end;
end;

/// <summary>Enthält der Attribut-Knoten einen TestCase/NamedTestCase?</summary>
function HasTestCase(AAttribute: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to AAttribute.ChildCount - 1 do
  begin
    if MatchText(TDUnitXClasses.ItemName(AAttribute[mIndex]), ['TestCase', 'NamedTestCase']) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Nur Leerraum zwischen den Offsets?</summary>
function OnlyBlank(const AText: string; AFrom, ATo: Integer): Boolean;
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

type
  /// <summary>Sammelt die Fälle einer Methode und prüft, ob sie sich schreiben lassen.</summary>
  TTableReader = record
    Text: string;
    Table: TTestCaseTable;
    First, Last: TSyntaxNode;
    procedure Refuse(const AReason: string);
    procedure AddAttribute(AAttribute: TSyntaxNode);
    procedure CheckBetween(const AAttributes: TArray<TSyntaxNode>);
  end;

procedure TTableReader.Refuse(const AReason: string);
begin
  if Table.Editable then
  begin
    Table.Editable := False;
    Table.Reason := AReason;
  end;
end;

procedure TTableReader.AddAttribute(AAttribute: TSyntaxNode);
var
  mIndex: Integer;
  mCase: TDUnitXTestCase;
  mRow: TTestCaseRow;
begin
  if not HasTestCase(AAttribute) then
  begin
    Exit;
  end;
  if First = nil then
  begin
    First := AAttribute;
  end;
  Last := AAttribute;
  if AAttribute.ChildCount <> 1 then
  begin
    Refuse(cTexts[TTestCaseTableText.SharedBrackets].Fmt([SourceOf(Text, AAttribute)]));
  end;
  for mIndex := 0 to AAttribute.ChildCount - 1 do
  begin
    if not MatchText(TDUnitXClasses.ItemName(AAttribute[mIndex]), ['TestCase', 'NamedTestCase']) then
    begin
      Continue;
    end;
    mRow := Default(TTestCaseRow);
    mRow.Line := AAttribute.StartPos.Line;
    if TDUnitXTestCases.Read(AAttribute[mIndex], mCase) then
    begin
      mRow.Name := mCase.CaseName;
      mRow.Values := mCase.Values;
      mRow.Separator := mCase.Separator;
      ReadShape(Text, mCase, mRow);
      if (mRow.Form <> TTestCaseForm.ValuesOnly) and (mCase.Item[1].Kind <> TSyntaxKind.Literal) then
      begin
        Refuse(cTexts[TTestCaseTableText.NotLiteral].Fmt([SourceOf(Text, AAttribute)]));
      end;
    end
    else
    begin
      mRow.Separator := ',';
      mRow.AttributeName := SourceOf(Text, AAttribute[mIndex]);
      Refuse(cTexts[TTestCaseTableText.NotLiteral].Fmt([SourceOf(Text, AAttribute)]));
    end;
    Table.Rows := Table.Rows + [mRow];
  end;
end;

procedure TTableReader.CheckBetween(const AAttributes: TArray<TSyntaxNode>);
var
  mInside: Boolean;
  mPrevious, mAttribute: TSyntaxNode;
begin
  mInside := False;
  mPrevious := nil;
  for mAttribute in AAttributes do
  begin
    if mAttribute = First then
    begin
      mInside := True;
    end
    else if mInside then
    begin
      if not OnlyBlank(Text, mPrevious.EndOffset, mAttribute.StartOffset) then
      begin
        Refuse(cTexts[TTestCaseTableText.CodeBetween].Text);
      end;
      if not HasTestCase(mAttribute) then
      begin
        Table.Between := Table.Between + [SourceOf(Text, mAttribute)];
      end;
    end;
    mPrevious := mAttribute;
    if mAttribute = Last then
    begin
      Break;
    end;
  end;
end;

/// <summary>Tabelle der Methode AHeader; False ohne [TestCase].</summary>
function ReadTable(const AText, AFixture: string; AHeader: TSyntaxNode; const AEnums: TArray<string>;
  out ATable: TTestCaseTable): Boolean;
var
  mReader: TTableReader;
  mAttributes: TArray<TSyntaxNode>;
  mAttribute: TSyntaxNode;
begin
  mReader := Default(TTableReader);
  mReader.Text := AText;
  mReader.Table.Editable := True;
  mAttributes := AttributesBefore(AHeader);
  for mAttribute in mAttributes do
  begin
    mReader.AddAttribute(mAttribute);
  end;
  Result := mReader.First <> nil;
  if not Result then
  begin
    ATable := Default(TTestCaseTable);
    Exit;
  end;
  mReader.CheckBetween(mAttributes);
  mReader.Table.Fixture := AFixture;
  mReader.Table.Method := AHeader.Name;
  mReader.Table.MethodLine := AHeader.StartPos.Line;
  mReader.Table.FirstLine := mAttributes[0].StartPos.Line;
  mReader.Table.Columns := ColumnsOf(AHeader, AEnums);
  mReader.Table.Range := TTextRange.Create(mReader.First.StartPos, mReader.Last.EndPos);
  mReader.Table.Indent := TTextLines.IndentOf(AText, mReader.First.StartPos.Line);
  ATable := mReader.Table;
end;

class function TTestCaseTables.All(ATree: TSyntaxTree; const AText: string): TArray<TTestCaseTable>;
var
  mEnums: TArray<string>;
  mClass: TDUnitXClass;
  mMember: TDUnitXMember;
  mTable: TTestCaseTable;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) or not ContainsText(AText, 'TestCase') or
    not TUsesClauses.IsTestUnit(ATree.Tokens) then
  begin
    Exit;
  end;
  mEnums := TDUnitXTestCases.Enums(ATree.Root);
  for mClass in TDUnitXClasses.Collect(ATree.Root) do
  begin
    for mMember in mClass.Members do
    begin
      if (mMember.Node.Kind = TSyntaxKind.RoutineHeader) and
        ReadTable(AText, mClass.Name, mMember.Node, mEnums, mTable) then
      begin
        Result := Result + [mTable];
      end;
    end;
  end;
end;

class function TTestCaseTables.Find(ATree: TSyntaxTree; const AText: string; ALine: Integer;
  out ATable: TTestCaseTable): Boolean;
var
  mTable: TTestCaseTable;
begin
  for mTable in All(ATree, AText) do
  begin
    if (ALine >= mTable.FirstLine) and (ALine <= mTable.MethodLine) then
    begin
      ATable := mTable;
      Exit(True);
    end;
  end;
  ATable := Default(TTestCaseTable);
  Result := False;
end;

{ Prüfen }

/// <summary>Erstes Zeichen von ASeparator in AValue; #0 ohne.</summary>
function SeparatorIn(const AValue, ASeparator: string): Char;
var
  mChar: Char;
begin
  for mChar in AValue do
  begin
    if Pos(mChar, ASeparator) > 0 then
    begin
      Exit(mChar);
    end;
  end;
  Result := #0;
end;

class function TTestCaseTables.CellProblem(const AColumn: TTestCaseColumn; const AValue, ASeparator: string): string;
var
  mSeparator: Char;
begin
  mSeparator := SeparatorIn(AValue, ASeparator);
  if mSeparator <> #0 then
  begin
    Exit(cTexts[TTestCaseTableText.ValueHasSeparator].Fmt([mSeparator]));
  end;
  if TDUnitXTestCases.Fits(AValue, AColumn.Kind, AColumn.EnumNames) then
  begin
    Exit('');
  end;
  case AColumn.Kind of
    TDUnitXValueKind.Integer_:
      Result := cTexts[TTestCaseTableText.NotInteger].Fmt([AColumn.TypeName]);
    TDUnitXValueKind.Float:
      Result := cTexts[TTestCaseTableText.NotFloat].Fmt([AColumn.TypeName]);
    TDUnitXValueKind.Boolean_:
      Result := cTexts[TTestCaseTableText.NotBoolean].Fmt([AColumn.TypeName]);
  else
    Result := cTexts[TTestCaseTableText.NotEnum].Fmt([AColumn.TypeName,
      StringReplace(AColumn.EnumNames, ',', ', ', [rfReplaceAll])]);
  end;
end;

class function TTestCaseTables.RowProblem(const ATable: TTestCaseTable; const ARow: TTestCaseRow): string;
begin
  if ATable.Columns = nil then
  begin
    Result := cTexts[TTestCaseTableText.NoParameters].Fmt([ATable.Method]);
  end
  else if Length(ARow.Values) <> Length(ATable.Columns) then
  begin
    Result := cTexts[TTestCaseTableText.CountMismatch].Fmt([Length(ARow.Values), ATable.Method,
      Length(ATable.Columns)]);
  end
  else
  begin
    Result := '';
  end;
end;

{ Schreiben }

class function TTestCaseTables.NewRow(const ATable: TTestCaseTable; const AName: string;
  const AValues: TArray<string>): TTestCaseRow;
begin
  if ATable.Rows <> nil then
  begin
    Result := ATable.Rows[High(ATable.Rows)];
  end
  else
  begin
    Result := Default(TTestCaseRow);
    Result.Separator := ',';
    Result.AttributeName := 'TestCase';
  end;
  Result.Name := AName;
  Result.Values := AValues;
  Result.Line := -1;
  if (Result.Form = TTestCaseForm.ValuesOnly) and (AName <> '') then
  begin
    Result.Form := TTestCaseForm.Classic;
  end;
end;

/// <summary>Werte mit dem ersten Zeichen des Trennzeichens verbunden.</summary>
function JoinValues(const ARow: TTestCaseRow): string;
var
  mIndex: Integer;
  mSeparator: string;
begin
  mSeparator := Copy(ARow.Separator, 1, 1);
  Result := '';
  for mIndex := 0 to High(ARow.Values) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + mSeparator;
    end;
    Result := Result + ARow.Values[mIndex];
  end;
end;

class function TTestCaseTables.AttributeText(const ARow: TTestCaseRow): string;
var
  mArgs: string;
begin
  mArgs := TStringLiterals.Quote(JoinValues(ARow));
  if ARow.Form <> TTestCaseForm.ValuesOnly then
  begin
    mArgs := TStringLiterals.Quote(ARow.Name) + ', ' + mArgs;
  end;
  if ARow.HasSeparator or (ARow.Separator <> ',') or (ARow.Tail <> '') then
  begin
    mArgs := mArgs + ', ' + TStringLiterals.Quote(ARow.Separator);
  end;
  Result := '[' + ARow.AttributeName + '(' + mArgs + ARow.Tail + ')]';
end;

class function TTestCaseTables.Write(const ATable: TTestCaseTable; const ARows: TArray<TTestCaseRow>;
  const ALineEnd: string; out AEdit: TTextEdit; out AReason: string): Boolean;
var
  mText, mValue, mLine: string;
  mIndex: Integer;
  mSeparator: Char;
begin
  AEdit := Default(TTextEdit);
  AReason := ATable.Reason;
  if not ATable.Editable then
  begin
    Exit(False);
  end;
  if ARows = nil then
  begin
    AReason := cTexts[TTestCaseTableText.NoRows].Text;
    Exit(False);
  end;
  mText := '';
  for mLine in ATable.Between do
  begin
    mText := mText + mLine + ALineEnd + ATable.Indent;
  end;
  for mIndex := 0 to High(ARows) do
  begin
    for mValue in ARows[mIndex].Values do
    begin
      mSeparator := SeparatorIn(mValue, ARows[mIndex].Separator);
      if mSeparator <> #0 then
      begin
        AReason := cTexts[TTestCaseTableText.ValueHasSeparator].Fmt([mSeparator]);
        Exit(False);
      end;
    end;
    if mIndex > 0 then
    begin
      mText := mText + ALineEnd + ATable.Indent;
    end;
    mText := mText + AttributeText(ARows[mIndex]);
  end;
  AEdit := TTextEdit.Create(ATable.Range, mText);
  Result := True;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Testing.TestCaseTable', cTexts);

end.
