unit Atlas.Common.Lsp.CompletionJson;

// CompletionItem des LSP aus TCompletionItem (Code-Review S-01, Konzept 4.2 Schritt 5): die Felder unter
// data stehen als Tabelle von Schreibern in fester Reihenfolge statt als 30 if-Zweige. Das Gate NeedsData
// entscheidet wie bisher, ob data überhaupt geschrieben wird; Felder wie container oder depth allein reichen
// dafür nicht (heutiges Verhalten, siehe ToJsonOmitsDataBelowGate).

interface

uses
  System.JSON,
  Atlas.Common.Lsp.CompletionRequest;

/// <summary>CompletionItem[]; AFirstSort: sortText des ersten Eintrags (bei Teilergebnissen fortlaufend). Der
/// Aufrufer übernimmt das Array.</summary>
function CompletionItemsToJson(const AItems: TArray<TCompletionItem>; AFirstSort: Integer): TJSONArray;
/// <summary>CompletionList mit isIncomplete und den Einträgen ab AFirstSort. Der Aufrufer übernimmt das Objekt.
/// </summary>
function CompletionListToJson(const AItems: TArray<TCompletionItem>; AIncomplete: Boolean;
  AFirstSort: Integer): TJSONObject;
/// <summary>Bekommt der Eintrag ein data-Objekt? Nur mit Quelle, erwartetem Typ, Aktion, Bedingung, Bereich,
/// Ordinal, pinned, hint, Formular, Sender, Datenmenge, Freigabe oder uses-Gruppe (#469).</summary>
function NeedsData(const AItem: TCompletionItem): Boolean;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Lsp.Positions;

type
  /// <summary>Schreibt eine Gruppe von data-Feldern, wenn der Eintrag sie hat.</summary>
  TItemDataWriter = procedure(const AItem: TCompletionItem; AData: TJSONObject);

procedure WriteSource(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.SourceFile = '' then
  begin
    Exit;
  end;
  AData.AddPair('file', AItem.SourceFile);
  AData.AddPair('line', TJSONNumber.Create(AItem.SourcePosition.Line));
  AData.AddPair('character', TJSONNumber.Create(AItem.SourcePosition.Character));
end;

procedure WriteExpected(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.Expected = '' then
  begin
    Exit;
  end;
  AData.AddPair('expected', AItem.Expected);
  AData.AddPair('fits', TJSONBool.Create(AItem.Fits));
end;

procedure WriteAction(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.Action <> '' then
  begin
    AData.AddPair('action', AItem.Action);
  end;
end;

// Für die Atlas-Oberfläche: Herkunft, Vererbungstiefe, Helper, Überladungen (#419, #425, #456).
procedure WriteContainer(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.Container <> '' then
  begin
    AData.AddPair('container', AItem.Container);
  end;
end;

procedure WriteDepth(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.Depth > 0 then
  begin
    AData.AddPair('depth', TJSONNumber.Create(AItem.Depth));
  end;
end;

procedure WriteHelper(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.IsHelper then
  begin
    AData.AddPair('helper', TJSONBool.Create(True));
  end;
end;

procedure WriteParameters(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.HasParameters then
  begin
    AData.AddPair('parameters', TJSONBool.Create(True));
  end;
end;

// Bedingte Deklarationen (#476).
procedure WriteCondition(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.Condition <> '' then
  begin
    AData.AddPair('condition', AItem.Condition);
  end;
end;

// Zweig varianter Record-Felder (#846).
procedure WriteVariant(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.VariantBranch <> '' then
  begin
    AData.AddPair('variant', AItem.VariantBranch);
  end;
end;

procedure WriteUnavailable(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.Unavailable then
  begin
    AData.AddPair('unavailable', TJSONBool.Create(True));
  end;
end;

procedure WriteScope(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.Scope > 0 then
  begin
    AData.AddPair('scope', TJSONNumber.Create(AItem.Scope));
  end;
end;

// Aufzählungen und Mengen (#448).
procedure WriteOrdinal(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.Ordinal > 0 then
  begin
    AData.AddPair('ordinal', TJSONNumber.Create(AItem.Ordinal));
  end;
end;

procedure WriteSetOf(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.SetOf = '' then
  begin
    Exit;
  end;
  AData.AddPair('setOf', AItem.SetOf);
  AData.AddPair('checked', TJSONBool.Create(AItem.SetChecked));
  AData.AddPair('setRange', TLspPositions.RangeToJson(AItem.SetRange));
end;

// Verknüpfte Platzhalter in den weiteren Änderungen (#473).
procedure WriteLinked(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.LinkedEdits then
  begin
    AData.AddPair('linkedEdits', TJSONBool.Create(True));
  end;
end;

// case vervollständigen (#449).
procedure WritePinned(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.Pinned then
  begin
    AData.AddPair('pinned', TJSONBool.Create(True));
  end;
end;

procedure WriteCount(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.Count > 0 then
  begin
    AData.AddPair('count', TJSONNumber.Create(AItem.Count));
  end;
end;

// Unbekannter Name (#471).
procedure WriteUnknown(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.Unknown <> '' then
  begin
    AData.AddPair('unknown', AItem.Unknown);
  end;
end;

// Interface implementieren (#466).
procedure WriteBatch(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.Batch then
  begin
    AData.AddPair('batch', TJSONBool.Create(True));
  end;
end;

procedure WriteHint(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.Hint then
  begin
    AData.AddPair('hint', TJSONBool.Create(True));
  end;
end;

// Komponenten aus dem Formular (#455).
procedure WriteForm(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.Form <> '' then
  begin
    AData.AddPair('form', AItem.Form);
  end;
end;

procedure WriteByType(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.ByType then
  begin
    AData.AddPair('byType', TJSONBool.Create(True));
  end;
end;

// Sender mit Typumwandlung (#480).
procedure WriteSender(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.Sender = '' then
  begin
    Exit;
  end;
  AData.AddPair('sender', AItem.Sender);
  AData.AddPair('senderOf', AItem.SenderOf);
end;

// Typkonvertierung (#490): Umwandlungseintrag und Hinweis bei Gleitkomma nach Ganzzahl.
procedure WriteConversion(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.Conversion <> '' then
  begin
    AData.AddPair('conversion', AItem.Conversion);
    AData.AddPair('convertFrom', AItem.ConvertFrom);
  end;
  if AItem.Lossy <> '' then
  begin
    AData.AddPair('lossy', AItem.Lossy);
  end;
end;

// Alle Felder zuweisen (#491): Zeilen für die Liste mit Kontrollkästchen.
procedure WriteAssignments(const AItem: TCompletionItem; AData: TJSONObject);
var
  Lines: TJSONArray;
  Line: TJSONObject;
  Assignment: TCompletionAssignment;
begin
  if Length(AItem.Assignments) = 0 then
  begin
    Exit;
  end;
  Lines := TJSONArray.Create;
  AData.AddPair('assign', Lines);
  for Assignment in AItem.Assignments do
  begin
    Line := TJSONObject.Create;
    Line.AddPair('name', Assignment.Name);
    Line.AddPair('detail', Assignment.Detail);
    Line.AddPair('text', Assignment.Text);
    Lines.AddElement(Line);
  end;
end;

// Feld- und Parameternamen (#461).
procedure WriteDataSet(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.DataSet = '' then
  begin
    Exit;
  end;
  AData.AddPair('dataSet', AItem.DataSet);
  if AItem.DataSource <> '' then
  begin
    AData.AddPair('dataSource', AItem.DataSource);
  end;
end;

// Freigabe absichern (#489).
procedure WriteGuard(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.Guard <> '' then
  begin
    AData.AddPair('guard', AItem.Guard);
  end;
end;

procedure WriteUnit(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.UnitName <> '' then
  begin
    AData.AddPair('unit', AItem.UnitName);
  end;
end;

/// <summary>Exception-Klassen (#483): Gruppe und früherer Zweig, der die Klasse schon fängt.</summary>
procedure WriteException(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.ExceptionGroup <> '' then
  begin
    AData.AddPair('exceptionGroup', AItem.ExceptionGroup);
  end;
  if AItem.Unreachable <> '' then
  begin
    AData.AddPair('unreachable', AItem.Unreachable);
  end;
end;

/// <summary>Mitglied eines with-Objekts (#481): Ausdruck und verdeckte Namen.</summary>
procedure WriteWith(const AItem: TCompletionItem; AData: TJSONObject);
var
  Shadows: TJSONArray;
  Text: string;
begin
  if AItem.WithOrigin = '' then
  begin
    Exit;
  end;
  AData.AddPair('withOrigin', AItem.WithOrigin);
  if Length(AItem.WithShadows) = 0 then
  begin
    Exit;
  end;
  Shadows := TJSONArray.Create;
  AData.AddPair('withShadows', Shadows);
  for Text in AItem.WithShadows do
  begin
    Shadows.Add(Text);
  end;
end;

procedure WriteHides(const AItem: TCompletionItem; AData: TJSONObject);
var
  Hides: TJSONArray;
  Text: string;
begin
  if Length(AItem.Hides) = 0 then
  begin
    Exit;
  end;
  Hides := TJSONArray.Create;
  AData.AddPair('hides', Hides);
  for Text in AItem.Hides do
  begin
    Hides.Add(Text);
  end;
end;

procedure WriteOverloads(const AItem: TCompletionItem; AData: TJSONObject);
var
  Overloads: TJSONArray;
  Position: TTextPosition;
begin
  if Length(AItem.Overloads) = 0 then
  begin
    Exit;
  end;
  Overloads := TJSONArray.Create;
  AData.AddPair('overloads', Overloads);
  for Position in AItem.Overloads do
  begin
    Overloads.AddElement(TJSONObject.Create.AddPair('line', TJSONNumber.Create(Position.Line))
      .AddPair('character', TJSONNumber.Create(Position.Character)));
  end;
end;

/// <summary>Typargument (#450): typeParam, constraint, constraintHint, hiddenKinds.</summary>
procedure WriteTypeArg(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.TypeParam = '' then
  begin
    Exit;
  end;
  AData.AddPair('typeParam', AItem.TypeParam);
  if AItem.Constraint <> '' then
  begin
    AData.AddPair('constraint', AItem.Constraint);
  end;
  if AItem.ConstraintHint <> '' then
  begin
    AData.AddPair('constraintHint', AItem.ConstraintHint);
  end;
  if AItem.HiddenKinds <> '' then
  begin
    AData.AddPair('hiddenKinds', AItem.HiddenKinds);
  end;
end;

/// <summary>Gebundene Typparameter (#450) für completionItem/resolve.</summary>
procedure WriteBindings(const AItem: TCompletionItem; AData: TJSONObject);
var
  Bindings: TJSONArray;
  Text: string;
begin
  if Length(AItem.Bindings) = 0 then
  begin
    Exit;
  end;
  Bindings := TJSONArray.Create;
  AData.AddPair('bindings', Bindings);
  for Text in AItem.Bindings do
  begin
    Bindings.Add(Text);
  end;
end;

procedure WriteUses(const AItem: TCompletionItem; AData: TJSONObject);
var
  List: TJSONArray;
  Text: string;
begin
  if AItem.UsesGroup = '' then
  begin
    Exit;
  end;
  AData.AddPair('usesGroup', AItem.UsesGroup);
  AData.AddPair('usesFilter', AItem.UsesFilter);
  if AItem.UsesElsewhere <> '' then
  begin
    AData.AddPair('usesElsewhere', AItem.UsesElsewhere);
  end;
  if AItem.UsesCycle <> '' then
  begin
    AData.AddPair('usesCycle', AItem.UsesCycle);
  end;
  List := TJSONArray.Create;
  AData.AddPair('usesTypes', List);
  for Text in AItem.UsesTypes do
  begin
    List.Add(Text);
  end;
  AData.AddPair('usesTypeCount', TJSONNumber.Create(AItem.UsesTypeCount));
  if Length(AItem.UsesHidden) > 0 then
  begin
    List := TJSONArray.Create;
    AData.AddPair('usesHidden', List);
    for Text in AItem.UsesHidden do
    begin
      List.Add(Text);
    end;
  end;
end;

procedure WriteInherited(const AItem: TCompletionItem; AData: TJSONObject);
var
  List: TJSONArray;
  Text: string;
begin
  if AItem.InheritedMatch <> '' then
  begin
    AData.AddPair('inheritedMatch', AItem.InheritedMatch);
  end;
  if Length(AItem.InheritedAbstract) > 0 then
  begin
    List := TJSONArray.Create;
    AData.AddPair('inheritedAbstract', List);
    for Text in AItem.InheritedAbstract do
    begin
      List.Add(Text);
    end;
  end;
end;

procedure WriteSameName(const AItem: TCompletionItem; AData: TJSONObject);
var
  List: TJSONArray;
  Text: string;
begin
  if Length(AItem.SameNameUnits) = 0 then
  begin
    Exit;
  end;
  if AItem.SameNameActive then
  begin
    AData.AddPair('sameNameActive', TJSONBool.Create(True));
  end;
  if AItem.SameNameOf <> '' then
  begin
    AData.AddPair('sameNameOf', AItem.SameNameOf);
    AData.AddPair('sameNameInsert', AItem.SameNameInsert);
  end;
  List := TJSONArray.Create;
  AData.AddPair('sameNameUnits', List);
  for Text in AItem.SameNameUnits do
  begin
    List.Add(Text);
  end;
  if Length(AItem.SameNameHidden) > 0 then
  begin
    List := TJSONArray.Create;
    AData.AddPair('sameNameHidden', List);
    for Text in AItem.SameNameHidden do
    begin
      List.Add(Text);
    end;
  end;
end;

/// <summary>Attribut nach "[" (#465).</summary>
procedure WriteAttribute(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.Attribute then
  begin
    AData.AddPair('attribute', TJSONBool.Create(True));
  end;
end;

/// <summary>Gerüst einer anonymen Methode (#468): erwarteter Methodenreferenztyp.</summary>
procedure WriteMethodRef(const AItem: TCompletionItem; AData: TJSONObject);
begin
  if AItem.MethodRef <> '' then
  begin
    AData.AddPair('methodRef', AItem.MethodRef);
  end;
end;

const
  /// <summary>Reihenfolge der Felder unter data; das Plugin liest nach Namen, die Golden-Tests nach Text.
  /// </summary>
  DataWriters: array[0..37] of TItemDataWriter = (WriteSource, WriteExpected, WriteAction, WriteContainer,
    WriteDepth, WriteHelper, WriteParameters, WriteCondition, WriteVariant, WriteUnavailable, WriteScope, WriteOrdinal,
    WriteSetOf, WriteLinked, WritePinned, WriteCount, WriteUnknown, WriteBatch, WriteHint, WriteForm, WriteByType, WriteSender,
    WriteConversion, WriteAssignments, WriteDataSet, WriteGuard, WriteUnit, WriteHides, WriteOverloads, WriteTypeArg,
    WriteBindings, WriteUses, WriteInherited, WriteSameName, WriteAttribute,
    WriteMethodRef, WriteWith, WriteException);

function NeedsData(const AItem: TCompletionItem): Boolean;
begin
  Result := (AItem.SourceFile <> '') or (AItem.Expected <> '') or (AItem.Action <> '') or (AItem.Condition <> '') or
    (AItem.VariantBranch <> '') or (AItem.Scope > 0) or (AItem.Ordinal > 0) or AItem.Pinned or AItem.LinkedEdits or
    AItem.Hint or (AItem.Form <> '') or
    (AItem.Sender <> '') or (AItem.DataSet <> '') or (AItem.Guard <> '') or (AItem.TypeParam <> '') or
    (Length(AItem.Bindings) > 0) or (AItem.Conversion <> '') or (AItem.Lossy <> '') or
    (Length(AItem.Assignments) > 0) or (AItem.UsesGroup <> '') or (AItem.InheritedMatch <> '') or
    (Length(AItem.InheritedAbstract) > 0) or (Length(AItem.SameNameUnits) > 0) or AItem.Attribute or
    (AItem.MethodRef <> '') or (AItem.ExceptionGroup <> '') or (AItem.Unreachable <> '');
end;

function EditToJson(const AEdit: TRuleEdit): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('range', TLspPositions.RangeToJson(AEdit.Range));
  Result.AddPair('newText', AEdit.NewText);
end;

function ItemToJson(const AItem: TCompletionItem; ASort: Integer): TJSONObject;
var
  Edits, Arguments: TJSONArray;
  Command: TJSONObject;
  Argument: string;
  Edit: TRuleEdit;
  Data: TJSONObject;
  Writer: TItemDataWriter;
begin
  Result := TJSONObject.Create;
  Result.AddPair('label', AItem.Name);
  Result.AddPair('kind', TJSONNumber.Create(AItem.Kind));
  if AItem.Detail <> '' then
  begin
    Result.AddPair('detail', AItem.Detail);
  end;
  if AItem.FilterText <> '' then
  begin
    Result.AddPair('filterText', AItem.FilterText);
  end;
  if AItem.HasTextEdit then
  begin
    Result.AddPair('textEdit', EditToJson(AItem.TextEdit));
  end
  else if AItem.InsertText <> '' then
  begin
    Result.AddPair('insertText', AItem.InsertText);
  end;
  // Code-Vorlagen mit Platzhaltern (#51): InsertTextFormat.Snippet.
  if AItem.Snippet then
  begin
    Result.AddPair('insertTextFormat', TJSONNumber.Create(2));
  end;
  if Length(AItem.AdditionalEdits) > 0 then
  begin
    Edits := TJSONArray.Create;
    Result.AddPair('additionalTextEdits', Edits);
    for Edit in AItem.AdditionalEdits do
    begin
      Edits.AddElement(EditToJson(Edit));
    end;
  end;
  // Befehl nach dem Übernehmen (#473): resourcestring in eine andere Unit schreiben.
  if AItem.Command <> '' then
  begin
    Command := TJSONObject.Create;
    Command.AddPair('title', AItem.CommandTitle);
    Command.AddPair('command', AItem.Command);
    Arguments := TJSONArray.Create;
    for Argument in AItem.CommandArguments do
    begin
      Arguments.Add(Argument);
    end;
    Command.AddPair('arguments', Arguments);
    Result.AddPair('command', Command);
  end;
  // Reihenfolge wie geliefert: beste Punktzahl, dann nächster Gültigkeitsbereich.
  Result.AddPair('sortText', Format('%.5d', [ASort]));
  if not NeedsData(AItem) then
  begin
    Exit;
  end;
  Data := TJSONObject.Create;
  for Writer in DataWriters do
  begin
    Writer(AItem, Data);
  end;
  Result.AddPair('data', Data);
end;

function CompletionItemsToJson(const AItems: TArray<TCompletionItem>; AFirstSort: Integer): TJSONArray;
var
  Index: Integer;
begin
  Result := TJSONArray.Create;
  for Index := 0 to High(AItems) do
  begin
    Result.AddElement(ItemToJson(AItems[Index], AFirstSort + Index));
  end;
end;

function CompletionListToJson(const AItems: TArray<TCompletionItem>; AIncomplete: Boolean;
  AFirstSort: Integer): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('isIncomplete', TJSONBool.Create(AIncomplete));
  Result.AddPair('items', CompletionItemsToJson(AItems, AFirstSort));
end;

end.
