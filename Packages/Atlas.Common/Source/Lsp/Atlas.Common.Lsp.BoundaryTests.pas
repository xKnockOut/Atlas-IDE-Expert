unit Atlas.Common.Lsp.BoundaryTests;

// Grenzfälle als [TestCase] in die Testunit übernehmen (#2173). Befehl atlas.server.boundaryTests
// [uri, zeile, fälle, kommentar?, platzhalter?]:
//   uri, zeile: die Routine in der Unit (zeile 0-basiert, irgendwo in der Routine);
//   fälle: [{name, values: [..Werte aller Parameter..], expected}], expected '' bei Prozeduren;
//   kommentar (optional): Zeile über den Fällen ohne //, etwa „heutiges Verhalten, nicht geprüft“;
//   platzhalter (optional, true): fehlendes expected bekommt den Platzhalter des Ergebnistyps (für „Heutiges
//   Ergebnis übernehmen“, das danach die Werte des Laufs einträgt); sonst ist ein fehlendes expected ein Grund.
// Bei Prozeduren entfällt expected.
// Gibt es in der Testunit schon die Testmethode Test<Routine>Cases mit [TestCase], kommen die Fälle als neue
// Zeilen dazu (wie die TestCase-Tabelle, #1879); sonst entsteht sie mit Parametern der Routine und AExpected.
// Antwort: { uri, method, appended, edit: WorkspaceEdit | null, reason }. Ein Edit für die ganze Testunit: ein
// Rückgängig-Schritt im Editor. DUnitX kennt in den Werten keine Anführung; das Trennzeichen ist das erste aus
// , ; | #, das in keinem Wert vorkommt.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.TestUnits,
  Atlas.Common.Editing.TestDrafts,
  Atlas.Common.Rules.Builtin.Testing.TestCaseTable;

type
  TLspBoundaryTestCase = record
    Name: string;
    /// <summary>Werte aller Parameter der Routine in der Schreibweise von [TestCase].</summary>
    Values: TArray<string>;
    /// <summary>Erwartetes Ergebnis; '' bei Prozeduren.</summary>
    Expected: string;
  end;

  /// <summary>Ergebnis der Übernahme in den Text einer Testunit.</summary>
  TLspBoundaryPlan = record
    NewText: string;
    Method: string;
    /// <summary>Zeilen an eine vorhandene Testmethode angefügt?</summary>
    Appended: Boolean;
    Reason: string;
  end;

  TLspBoundaryTests = class
  public const
    cCommand = 'atlas.server.boundaryTests';
    cMethodSuffix = 'Cases';
    cSeparators: array[0..3] of string = (',', ';', '|', '#');
  public
    /// <summary>Erstes Trennzeichen, das in keinem Wert vorkommt; '' wenn jedes vorkommt.</summary>
    class function SeparatorFor(const ACases: TArray<TLspBoundaryTestCase>): string; static;
    /// <summary>Zeilen der Tabelle für die Fälle: Werte und, wenn gesetzt, das erwartete Ergebnis; Namen
    /// eindeutig (Nummer dahinter) gegenüber ATaken und untereinander.</summary>
    class function Rows(const ACases: TArray<TLspBoundaryTestCase>; const ASeparator: string;
      const ATaken: TArray<string>): TArray<TTestCaseRow>; static;
    /// <summary>Übernimmt die Fälle für ADraft in die Testunit ATestText; False mit Reason im Plan.</summary>
    class function Plan(const ADraft: TTestDraft; const ACases: TArray<TLspBoundaryTestCase>;
      const ATestText, AComment: string): TLspBoundaryPlan; static;
    /// <summary>Erwartete Werte passend zur Routine: bei Prozeduren keine, bei Funktionen fehlende mit dem
    /// Platzhalter (APlaceholders) bzw. False mit AReason.</summary>
    class function Completed(const ADraft: TTestDraft; var ACases: TArray<TLspBoundaryTestCase>;
      APlaceholders: Boolean; out AReason: string): Boolean; static;
    /// <summary>Fälle aus dem JSON der Anfrage.</summary>
    class function CasesFromJson(AArray: TJSONArray): TArray<TLspBoundaryTestCase>; static;
    class function Execute(ATestUnits: TLspTestUnits; const AArguments: TJSONArray): TJSONValue; static;
    /// <summary>Meldet den Befehl an (nebenläufig: liest nur); ATestUnits bleibt beim Aufrufer.</summary>
    class procedure Attach(ACommands: TLspCommands; ATestUnits: TLspTestUnits); static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  TLspBoundaryTestsText = (NeedsArguments, NoCases, NoSeparator, NotTestCase, NoExpected);

const
  cTexts: array[TLspBoundaryTestsText] of TAtlasText = (
    (De: '%s braucht URI, Zeile und Fälle'; En: '%s needs a URI, a line and cases'),
    (De: 'Keine Fälle ausgewählt'; En: 'No cases selected'),
    (De: 'Jeder Wert enthält eines der Trennzeichen , ; | #; DUnitX kann die Werte nicht übergeben';
     En: 'The values contain each of the separators , ; | #; DUnitX cannot pass them'),
    (De: '%s hat var- oder out-Parameter oder einen ohne Typ; [TestCase] kann sie nicht füllen';
     En: '%s has var or out parameters or one without a type; [TestCase] cannot fill them'),
    (De: 'Fall „%s“: erwartetes Ergebnis fehlt'; En: 'Case “%s”: expected result is missing'));

{$SCOPEDENUMS OFF}

class function TLspBoundaryTests.SeparatorFor(const ACases: TArray<TLspBoundaryTestCase>): string;
var
  mSeparator, mValue: string;
  mCase: TLspBoundaryTestCase;
  mUsed: Boolean;
begin
  for mSeparator in cSeparators do
  begin
    mUsed := False;
    for mCase in ACases do
    begin
      for mValue in mCase.Values + [mCase.Expected] do
      begin
        mUsed := mUsed or (Pos(mSeparator, mValue) > 0);
      end;
    end;
    if not mUsed then
    begin
      Exit(mSeparator);
    end;
  end;
  Result := '';
end;

/// <summary>AName oder AName2, AName3 …, was nicht in ATaken steht.</summary>
function FreeName(const AName: string; const ATaken: TArray<string>): string;
var
  mNumber: Integer;
begin
  Result := AName;
  mNumber := 1;
  while MatchText(Result, ATaken) do
  begin
    Inc(mNumber);
    Result := AName + ' ' + IntToStr(mNumber);
  end;
end;

class function TLspBoundaryTests.Rows(const ACases: TArray<TLspBoundaryTestCase>; const ASeparator: string;
  const ATaken: TArray<string>): TArray<TTestCaseRow>;
var
  mCase: TLspBoundaryTestCase;
  mRow: TTestCaseRow;
  mTaken: TArray<string>;
begin
  Result := nil;
  mTaken := ATaken;
  for mCase in ACases do
  begin
    mRow := Default(TTestCaseRow);
    mRow.Name := FreeName(Trim(mCase.Name), mTaken);
    mTaken := mTaken + [mRow.Name];
    mRow.Values := mCase.Values;
    if mCase.Expected <> '' then
    begin
      mRow.Values := mRow.Values + [mCase.Expected];
    end;
    mRow.Separator := ASeparator;
    mRow.HasSeparator := ASeparator <> ',';
    mRow.AttributeName := 'TestCase';
    mRow.Line := -1;
    Result := Result + [mRow];
  end;
end;

/// <summary>Kann [TestCase] alle Parameter füllen (Typ, kein var/out)?</summary>
function Fillable(const ADraft: TTestDraft): Boolean;
var
  mValue: TTestDraftValue;
begin
  for mValue in ADraft.Parameters do
  begin
    if (mValue.TypeName = '') or MatchText(mValue.Modifier, ['var', 'out']) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

/// <summary>Vorhandene Tabelle der Testmethode AMethod in AFixture.</summary>
function ExistingTable(const AText, AFixture, AMethod: string; out ATable: TTestCaseTable): Boolean;
var
  mTree: TSyntaxTree;
  mTable: TTestCaseTable;
begin
  Result := False;
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    for mTable in TTestCaseTables.All(mTree, AText) do
    begin
      if SameText(mTable.Method, AMethod) and SameText(mTable.Fixture, AFixture) then
      begin
        ATable := mTable;
        Exit(True);
      end;
    end;
  finally
    mTree.Free;
  end;
end;

/// <summary>Text mit dem Edit AEdit.</summary>
function Applied(const AText: string; const AEdit: TTextEdit): string;
var
  mTable: TLineTable;
  mStart, mStop: Integer;
begin
  mTable := TLineTable.Build(AText);
  mStart := mTable.OffsetAt(AEdit.Range.StartPos);
  mStop := mTable.OffsetAt(AEdit.Range.EndPos);
  Result := Copy(AText, 1, mStart) + AEdit.NewText + Copy(AText, mStop + 1, MaxInt);
end;

/// <summary>Kommentarzeile // AComment über Zeile ALine, wenn sie dort noch nicht steht.</summary>
function WithComment(const AText, AComment, AIndent: string; ALine: Integer): string;
var
  mLineBreak: string;
  mLines: TArray<string>;
begin
  Result := AText;
  if AComment = '' then
  begin
    Exit;
  end;
  mLineBreak := TTextLines.LineBreakOf(AText);
  mLines := AText.Split([mLineBreak]);
  if (ALine > 0) and (Trim(mLines[ALine - 1]) = '// ' + AComment) then
  begin
    Exit;
  end;
  mLines[ALine] := AIndent + '// ' + AComment + mLineBreak + mLines[ALine];
  Result := string.Join(mLineBreak, mLines);
end;

function AppendPlan(const ATable: TTestCaseTable; const ACases: TArray<TLspBoundaryTestCase>;
  const ATestText, AComment: string): TLspBoundaryPlan;
var
  mNames: TArray<string>;
  mRow: TTestCaseRow;
  mEdit: TTextEdit;
  mReason: string;
begin
  Result := Default(TLspBoundaryPlan);
  Result.Method := ATable.Method;
  Result.Appended := True;
  mNames := nil;
  for mRow in ATable.Rows do
  begin
    mNames := mNames + [mRow.Name];
  end;
  // Neue Zeilen übernehmen Form und Trennzeichen der letzten; Write lehnt Werte mit Trennzeichen ab.
  mRow := TTestCaseTables.NewRow(ATable, '', nil);
  if not TTestCaseTables.Write(ATable, ATable.Rows + TLspBoundaryTests.Rows(ACases, mRow.Separator, mNames),
    TTextLines.LineBreakOf(ATestText), mEdit, mReason) then
  begin
    Result.Reason := mReason;
    Exit;
  end;
  Result.NewText := WithComment(Applied(ATestText, mEdit), AComment, ATable.Indent, ATable.FirstLine);
end;

function NewMethodPlan(const ADraft: TTestDraft; const ACases: TArray<TLspBoundaryTestCase>;
  const ATestText, AComment: string): TLspBoundaryPlan;
var
  mDraft: TTestDraft;
  mSeparator, mName, mReason: string;
  mRow: TTestCaseRow;
begin
  Result := Default(TLspBoundaryPlan);
  mSeparator := TLspBoundaryTests.SeparatorFor(ACases);
  if mSeparator = '' then
  begin
    Result.Reason := cTexts[TLspBoundaryTestsText.NoSeparator].Text;
    Exit;
  end;
  mDraft := ADraft;
  mDraft.TestName := ADraft.TestName + TLspBoundaryTests.cMethodSuffix;
  mDraft.Parameterized := True;
  mDraft.Draft := False;
  mDraft.Attributes := nil;
  if AComment <> '' then
  begin
    mDraft.Attributes := ['// ' + AComment];
  end;
  for mRow in TLspBoundaryTests.Rows(ACases, mSeparator, nil) do
  begin
    mDraft.Attributes := mDraft.Attributes + [TTestCaseTables.AttributeText(mRow)];
  end;
  if not TTestDrafts.AddToTestUnit(ATestText, mDraft, False, Result.NewText, mName, mReason) then
  begin
    Result.Reason := mReason;
    Exit;
  end;
  Result.Method := mName;
end;

class function TLspBoundaryTests.Plan(const ADraft: TTestDraft; const ACases: TArray<TLspBoundaryTestCase>;
  const ATestText, AComment: string): TLspBoundaryPlan;
var
  mTable: TTestCaseTable;
begin
  if Length(ACases) = 0 then
  begin
    Result := Default(TLspBoundaryPlan);
    Result.Reason := cTexts[TLspBoundaryTestsText.NoCases].Text;
  end
  else if not Fillable(ADraft) then
  begin
    Result := Default(TLspBoundaryPlan);
    Result.Reason := cTexts[TLspBoundaryTestsText.NotTestCase].Fmt([ADraft.Target]);
  end
  else if ExistingTable(ATestText, ADraft.Fixture, ADraft.TestName + cMethodSuffix, mTable) then
  begin
    Result := AppendPlan(mTable, ACases, ATestText, AComment);
  end
  else
  begin
    Result := NewMethodPlan(ADraft, ACases, ATestText, AComment);
  end;
end;

/// <summary>Platzhalter des Typs als Wert für [TestCase]: '' statt des Literals '' und für Default(T).</summary>
function PlaceholderValue(const ATypeName: string): string;
begin
  Result := TTestDrafts.Placeholder(ATypeName);
  if (Result = '''''') or StartsText('Default(', Result) then
  begin
    Result := '';
  end;
end;

class function TLspBoundaryTests.Completed(const ADraft: TTestDraft; var ACases: TArray<TLspBoundaryTestCase>;
  APlaceholders: Boolean; out AReason: string): Boolean;
var
  mIndex: Integer;
begin
  AReason := '';
  for mIndex := 0 to High(ACases) do
  begin
    if ADraft.ResultType = '' then
    begin
      ACases[mIndex].Expected := '';
    end
    else if (ACases[mIndex].Expected = '') and APlaceholders then
    begin
      ACases[mIndex].Expected := PlaceholderValue(ADraft.ResultType);
    end
    else if Trim(ACases[mIndex].Expected) = '' then
    begin
      AReason := cTexts[TLspBoundaryTestsText.NoExpected].Fmt([ACases[mIndex].Name]);
      Exit(False);
    end;
  end;
  Result := True;
end;

function StringsOf(AObject: TJSONObject; const AName: string): TArray<string>;
var
  mArray: TJSONArray;
  mIndex: Integer;
begin
  Result := nil;
  if not AObject.TryGetValue<TJSONArray>(AName, mArray) then
  begin
    Exit;
  end;
  for mIndex := 0 to mArray.Count - 1 do
  begin
    Result := Result + [mArray.Items[mIndex].Value];
  end;
end;

class function TLspBoundaryTests.CasesFromJson(AArray: TJSONArray): TArray<TLspBoundaryTestCase>;
var
  mIndex: Integer;
  mObject: TJSONObject;
  mCase: TLspBoundaryTestCase;
begin
  Result := nil;
  for mIndex := 0 to AArray.Count - 1 do
  begin
    if not (AArray.Items[mIndex] is TJSONObject) then
    begin
      Continue;
    end;
    mObject := TJSONObject(AArray.Items[mIndex]);
    mCase := Default(TLspBoundaryTestCase);
    if not mObject.TryGetValue<string>('name', mCase.Name) then
    begin
      mCase.Name := '';
    end;
    if not mObject.TryGetValue<string>('expected', mCase.Expected) then
    begin
      mCase.Expected := '';
    end;
    mCase.Values := StringsOf(mObject, 'values');
    Result := Result + [mCase];
  end;
end;

function PlanJson(const ATestFile, AOld: string; const APlan: TLspBoundaryPlan): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('uri', TDocumentUris.FromPath(ATestFile));
  Result.AddPair('method', APlan.Method);
  Result.AddPair('appended', TJSONBool.Create(APlan.Appended));
  if (APlan.Reason = '') and (ATestFile <> '') then
  begin
    Result.AddPair('edit', TLspTestUnits.ChangeEditOf(ATestFile, AOld, APlan.NewText));
  end
  else
  begin
    Result.AddPair('edit', TJSONNull.Create);
  end;
  Result.AddPair('reason', APlan.Reason);
end;

class function TLspBoundaryTests.Execute(ATestUnits: TLspTestUnits; const AArguments: TJSONArray): TJSONValue;
var
  mDraft: TTestDraft;
  mFile, mText, mReason, mComment: string;
  mPlan: TLspBoundaryPlan;
  mCases: TArray<TLspBoundaryTestCase>;
  mPlaceholders: Boolean;
begin
  if (AArguments = nil) or (AArguments.Count < 3) or not (AArguments.Items[0] is TJSONString) or
    not (AArguments.Items[1] is TJSONNumber) or not (AArguments.Items[2] is TJSONArray) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TLspBoundaryTestsText.NeedsArguments].Fmt([cCommand]));
  end;
  mComment := '';
  if (AArguments.Count > 3) and (AArguments.Items[3] is TJSONString) then
  begin
    mComment := Trim(AArguments.Items[3].Value);
  end;
  mPlaceholders := (AArguments.Count > 4) and (AArguments.Items[4] is TJSONBool) and
    TJSONBool(AArguments.Items[4]).AsBoolean;
  mCases := CasesFromJson(TJSONArray(AArguments.Items[2]));
  mPlan := Default(TLspBoundaryPlan);
  if ATestUnits.DraftWithTestUnit(AArguments.Items[0].Value, TJSONNumber(AArguments.Items[1]).AsInt, mDraft, mFile,
    mText, mReason) then
  begin
    if Completed(mDraft, mCases, mPlaceholders, mReason) then
    begin
      mPlan := Plan(mDraft, mCases, mText, mComment);
    end
    else
    begin
      mPlan.Reason := mReason;
    end;
  end
  else
  begin
    mPlan.Reason := mReason;
  end;
  Result := PlanJson(mFile, mText, mPlan);
end;

class procedure TLspBoundaryTests.Attach(ACommands: TLspCommands; ATestUnits: TLspTestUnits);
begin
  ACommands.RegisterConcurrent(cCommand,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := Execute(ATestUnits, AArguments);
    end);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.BoundaryTests', cTexts);

end.
