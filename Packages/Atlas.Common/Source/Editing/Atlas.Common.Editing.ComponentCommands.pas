unit Atlas.Common.Editing.ComponentCommands;

// Schnellbefehle für eigene Komponenten (#320) im Rahmen aus #293:
//   /notify OnChange[: Typ]  Ereignisfeld, Property und DoChange-Methode
//   /changed Farbe           Setter der Property nach dem Muster "if F <> Value then
//                            begin F := Value; Changed; end" (Invalidate bei Controls)
//   /loaded                  Loaded mit inherited (nur TComponent-Nachfahren)
//   /notification [FFeld]    Notification für Komponentenfelder und FreeNotification im Setter
//   /event Button1.OnClick   Handler mit der Signatur des Ereignistyps im Formular anlegen und in der
//                            DFM bzw. FMX zuweisen (#295); "/event OnCreate" für das Formular selbst
// Ob eine Klasse von TComponent bzw. TControl abstammt, ergibt sich aus der
// Vorfahrenkette in der Unit und im Symbolindex.

interface

uses
  Atlas.Common.Editing.Contract;

/// <summary>Trägt /notify, /changed, /loaded, /notification und /event über ARegister ein.</summary>
procedure RegisterComponentCommands(const ARegister: TSlashRegister);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.ClassCompletion,
  Atlas.Common.Editing.ClassCommands,
  Atlas.Text.Lines,
  Atlas.Common.Editing.ClassMembers,
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TComponentCommandsText = (ExpectedIsNotifyOnNameEventType, NotifyOnlyAppliesInA, EventTypeNotFoundProcedure,
    ChangedOnlyAppliesInA, HasNoProperty, BodyOfNotFound, TypeOfNotRecognized, MultiLinePropertyDeclarationPlease,
    ExpectedIsChangedProperty, LoadedOnlyAppliesInA, DoesNotDescendFromTComponent, NotificationOnlyAppliesInA,
    DoesNotDescendFromTComponent2, NoFieldsWithAComponent, HasNoField, HasNoEvent, ThereIsNoDfmOr, IsNotATextDFM,
    IsNotIn, IsAlreadyAssignedTo, EventOnlyAppliesInA, ExpectedIsEventButton1OnClick, EventNeedsTheEditor,
    EventWithFieldPropertyAnd, SetterWithChangeCheckAnd, OverrideLoaded, CreateAnEventHandlerAnd,
    NotificationForComponentFields, AlreadyHas, AlreadyHasLoaded, NotificationAlreadyHandlesTheseFields,
    ChangedColor);

const
  cTexts: array[TComponentCommandsText] of TAtlasText = (
    (De: 'Erwartet wird /notify OnName[: Ereignistyp]'; En: 'Expected is /notify OnName[: EventType]'),
    (De: '/notify gilt nur in einer Klasse oder einer ihrer Methoden';
     En: '/notify only applies in a class or one of its methods'),
    (De: 'Ereignistyp %s nicht gefunden (procedure(...) of object)';
     En: 'Event type %s not found (procedure(...) of object)'),
    (De: '/changed gilt nur in einer Klasse oder einer ihrer Methoden';
     En: '/changed only applies in a class or one of its methods'),
    (De: '%s hat keine Property %s'; En: '%s has no property %s'),
    (De: 'Rumpf von %s.%s nicht gefunden'; En: 'Body of %s.%s not found'),
    (De: 'Typ von %s nicht erkannt'; En: 'Type of %s not recognized'),
    (De: 'Mehrzeilige Property-Deklaration: Setter bitte mit /prop anlegen';
     En: 'Multi-line property declaration: please create the setter with /prop'),
    (De: 'Erwartet wird /changed Property'; En: 'Expected is /changed Property'),
    (De: '/loaded gilt nur in einer Klasse oder einer ihrer Methoden';
     En: '/loaded only applies in a class or one of its methods'),
    (De: '%s stammt nicht von TComponent ab; Loaded gibt es dort nicht';
     En: '%s does not descend from TComponent; Loaded does not exist there'),
    (De: '/notification gilt nur in einer Klasse oder einer ihrer Methoden';
     En: '/notification only applies in a class or one of its methods'),
    (De: '%s stammt nicht von TComponent ab'; En: '%s does not descend from TComponent'),
    (De: 'Keine Felder mit Komponententyp'; En: 'No fields with a component type'),
    (De: '%s hat kein Feld %s'; En: '%s has no field %s'),
    (De: '%s hat kein Ereignis %s'; En: '%s has no event %s'),
    (De: 'Neben der Unit liegt keine .dfm oder .fmx'; En: 'There is no .dfm or .fmx next to the unit'),
    (De: '%s ist keine Text-DFM'; En: '%s is not a text DFM'),
    (De: '%s steht nicht in %s'; En: '%s is not in %s'),
    (De: '%s ist schon %s zugewiesen'; En: '%s is already assigned to %s'),
    (De: '/event gilt nur in einer Formularklasse oder einer ihrer Methoden';
     En: '/event only applies in a form class or one of its methods'),
    (De: 'Erwartet wird /event Button1.OnClick bzw. /event OnCreate';
     En: 'Expected is /event Button1.OnClick or /event OnCreate'),
    (De: '/event braucht den Editor'; En: '/event needs the editor'),
    (De: 'Ereignis mit Feld, Property und Do-Methode'; En: 'Event with field, property and Do method'),
    (De: 'Setter mit Änderungsprüfung und Benachrichtigung'; En: 'Setter with change check and notification'),
    (De: 'Loaded überschreiben'; En: 'Override Loaded'),
    (De: 'Ereignis-Handler anlegen und in der DFM zuweisen'; En: 'Create an event handler and assign it in the DFM'),
    (De: 'Notification für Komponentenfelder'; En: 'Notification for component fields'),
    (De: '%s hat schon %s'; En: '%s already has %s'),
    (De: '%s hat schon Loaded'; En: '%s already has Loaded'),
    (De: 'Notification behandelt diese Felder schon'; En: 'Notification already handles these fields'),
    (De: '/changed Farbe'; En: '/changed Color'));

{$SCOPEDENUMS OFF}

/// <summary>Abschnitte vor "end" der Klasse: Feld in private (vorhandener Abschnitt oder neuer), dann AMore.</summary>
function AddToClass(ASource: TCommandSource; const AClass: TIndexSymbol; const AField: string;
  const AMore: array of string): TArray<TTextEdit>;
var
  mLine, mEndLine, mIndex: Integer;
  mIndent, mBody: string;
begin
  Result := nil;
  mEndLine := AClass.Range.EndPos.Line;
  mIndent := ASource.Indent(mEndLine);
  mBody := '';
  if AField <> '' then
  begin
    mLine := ASource.PrivateLine(AClass);
    if mLine >= 0 then
    begin
      Result := [ASource.AfterLine(mLine, ASource.Indent(mLine) + '  ' + AField)];
    end
    else
    begin
      mBody := mIndent + 'private' + ASource.LineBreak + mIndent + '  ' + AField;
    end;
  end;
  // AMore: abwechselnd Abschnitt und Deklaration.
  mIndex := 0;
  while mIndex < High(AMore) do
  begin
    if mBody <> '' then
    begin
      mBody := mBody + ASource.LineBreak;
    end;
    mBody := mBody + mIndent + AMore[mIndex] + ASource.LineBreak + mIndent + '  ' + AMore[mIndex + 1];
    Inc(mIndex, 2);
  end;
  if mBody <> '' then
  begin
    Result := Result + [ASource.BeforeLine(mEndLine, mBody)];
  end;
end;

{ /notify }

/// <summary>Text der Typdeklaration ATypeName in der Datei; '' ohne.</summary>
function LocalTypeText(ASource: TCommandSource; const ATypeName: string): string;
var
  mSymbol: TIndexSymbol;
begin
  Result := '';
  for mSymbol in ASource.UnitIndex.Symbols do
  begin
    if SameText(mSymbol.Name, ATypeName) and (mSymbol.Container = '') then
    begin
      Result := RangeText(ASource.Lines, mSymbol.Range);
    end;
  end;
end;

/// <summary>Typdeklaration ATypeName aus dem Index: der Kopf der Deklaration (#492), sonst der Text der Datei;
/// '' ohne.</summary>
function IndexedTypeText(const AIndex: ISymbolIndex; const ATypeName: string): string;
var
  mLocation: TSymbolLocation;
  mFileText: string;
begin
  Result := '';
  if AIndex = nil then
  begin
    Exit;
  end;
  for mLocation in AIndex.FindSymbols(ATypeName) do
  begin
    if ContainsText(mLocation.Symbol.Signature, 'of object') then
    begin
      Exit(mLocation.Symbol.Signature);
    end;
    if LoadText(mLocation.FileName, mFileText) then
    begin
      Exit(RangeText(mFileText.Replace(#13#10, #10).Split([#10]), mLocation.Symbol.Range));
    end;
  end;
end;

/// <summary>Methodenzeigertyp ATypeName: "procedure" bzw. "function", Parameterliste ohne Klammern und
/// Ergebnistyp ('' bei Prozeduren). False ohne "of object".</summary>
function EventSignature(ASource: TCommandSource; const AIndex: ISymbolIndex; const ATypeName: string;
  out AKind, AParameters, AResultType: string): Boolean;
var
  mText, mTail: string;
  mOpen, mClose, mOfPos: Integer;
begin
  AKind := 'procedure';
  AParameters := '';
  AResultType := '';
  if SameText(ATypeName, 'TNotifyEvent') then
  begin
    AParameters := 'Sender: TObject';
    Exit(True);
  end;
  mText := LocalTypeText(ASource, ATypeName);
  if mText = '' then
  begin
    mText := IndexedTypeText(AIndex, ATypeName);
  end;
  mOpen := Pos('(', mText);
  mClose := LastDelimiter(')', mText);
  mOfPos := Pos('of object', LowerCase(mText));
  Result := (mText <> '') and (mOfPos > 0);
  if not Result then
  begin
    Exit;
  end;
  if ContainsText(Copy(mText, 1, mOfPos), 'function') then
  begin
    AKind := 'function';
  end;
  if (mOpen > 0) and (mClose > mOpen) and (mClose < mOfPos) then
  begin
    AParameters := Trim(Copy(mText, mOpen + 1, mClose - mOpen - 1));
  end
  else
  begin
    mClose := Pos(AKind, LowerCase(mText)) + Length(AKind) - 1;
  end;
  // Ergebnis: zwischen ")" bzw. "function" und "of object" hinter dem Doppelpunkt.
  mTail := Trim(Copy(mText, mClose + 1, mOfPos - mClose - 1));
  if (AKind = 'function') and StartsStr(':', mTail) then
  begin
    AResultType := Trim(Copy(mTail, 2, MaxInt));
  end;
end;

/// <summary>Parameterliste des Ereignistyps ohne Klammern, z. B. "Sender: TObject; const AText: string".</summary>
function EventParameters(ASource: TCommandSource; const AIndex: ISymbolIndex; const ATypeName: string;
  out AParameters: string): Boolean;
var
  mKind, mResultType: string;
begin
  Result := EventSignature(ASource, AIndex, ATypeName, mKind, AParameters, mResultType);
end;

/// <summary>"/notify OnName[: Typ]" zerlegen; ohne Typ TNotifyEvent. False bei falscher Form.</summary>
function ParseNotifyArguments(const AArguments: string; out AName, ATypeName: string): Boolean;
begin
  if not SplitDeclaration(AArguments, ':', AName, ATypeName) then
  begin
    AName := Trim(AArguments);
    ATypeName := 'TNotifyEvent';
  end;
  Result := IsValidIdent(AName) and StartsText('On', AName) and (Length(AName) >= 3);
end;

/// <summary>Parameter der Do-Methode (AOwn, mit Klammern; '' ohne) und Argumente des Ereignisaufrufs (ANames):
/// Sender: TObject am Anfang setzt Self ein, die übrigen Parameter reicht DoX durch.</summary>
procedure NotifyParameters(const AParameters: string; out AOwn, ANames: string);
var
  mGroups: TArray<string>;
begin
  mGroups := AParameters.Split([';']);
  if (Length(mGroups) > 0) and ContainsText(mGroups[0], 'Sender') then
  begin
    AOwn := Trim(string.Join(';', Copy(mGroups, 1, MaxInt)));
    ANames := ParameterNames('(' + AOwn + ')');
    if ANames <> '' then
    begin
      ANames := 'Self, ' + ANames;
    end
    else
    begin
      ANames := 'Self';
    end;
  end
  else
  begin
    AOwn := AParameters;
    ANames := ParameterNames('(' + AOwn + ')');
  end;
  if AOwn <> '' then
  begin
    AOwn := '(' + AOwn + ')';
  end;
end;

/// <summary>published bei Komponenten, sonst public.</summary>
function PropertySection(ASource: TCommandSource; const AIndex: ISymbolIndex; const AClassName: string): string;
begin
  if DescendsFrom(Ancestors(ASource, AIndex, AClassName), cComponentRoots) then
  begin
    Result := 'published';
  end
  else
  begin
    Result := 'public';
  end;
end;

/// <summary>Die Klasse hat schon die Property AName oder das Feld AField.</summary>
function HasEvent(ASource: TCommandSource; const AClass: TIndexSymbol; const AName, AField: string): Boolean;
var
  mExisting: TIndexSymbol;
begin
  Result := FindMember(ASource, AClass, AName, [TIndexSymbolKind.Property_], mExisting) or
    FindMember(ASource, AClass, AField, [TIndexSymbolKind.Field], mExisting);
end;

function ExecuteNotify(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mClass: TIndexSymbol;
  mName, mTypeName, mField, mMethod, mParameters, mOwn, mNames, mLB: string;
begin
  AEdits := nil;
  if not ParseNotifyArguments(AContext.Arguments, mName, mTypeName) then
  begin
    Exit(Fail(cTexts[TComponentCommandsText.ExpectedIsNotifyOnNameEventType].Text, AReason));
  end;
  mField := 'F' + mName;
  mMethod := 'Do' + Copy(mName, 3, MaxInt);
  mSource := TCommandSource.Create(AContext);
  try
    if not mSource.ClassAt(mClass) then
    begin
      Exit(Fail(cTexts[TComponentCommandsText.NotifyOnlyAppliesInA].Text, AReason));
    end;
    if HasEvent(mSource, mClass, mName, mField) then
    begin
      Exit(Fail(cTexts[TComponentCommandsText.AlreadyHas].Fmt([mClass.Name, mName]), AReason));
    end;
    if not EventParameters(mSource, AContext.Index, mTypeName, mParameters) then
    begin
      Exit(Fail(cTexts[TComponentCommandsText.EventTypeNotFoundProcedure].Fmt([mTypeName]), AReason));
    end;
    NotifyParameters(mParameters, mOwn, mNames);
    mLB := mSource.LineBreak;
    AEdits := AddToClass(mSource, mClass, Format('%s: %s;', [mField, mTypeName]),
      ['protected', Format('procedure %s%s; virtual;', [mMethod, mOwn]),
      PropertySection(mSource, AContext.Index, mClass.Name),
      Format('property %s: %s read %s write %s;', [mName, mTypeName, mField, mField])]);
    AEdits := AEdits + [mSource.AddBody(mClass.Name, Format('procedure %s.%s%s;', [mClass.Name, mMethod,
      mOwn]) + mLB + 'begin' + mLB + Format('  if Assigned(%s) then', [mField]) + mLB + Format('    %s(%s);',
      [mField, mNames]) + mLB + 'end;'), mSource.RemoveCommand];
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /changed }

type
  /// <summary>Property, deren Setter /changed schreibt.</summary>
  TChangedTarget = record
    Source: TCommandSource;
    ClassSymbol: TIndexSymbol;
    Prop: TIndexSymbol;
    Name: string;
    /// <summary>Text der Property-Deklaration.</summary>
    Declaration: string;
    /// <summary>Feld hinter read, sonst F + Name.</summary>
    function Field: string;
    /// <summary>Name hinter write; '' ohne.</summary>
    function Writer: string;
    function Find(out AReason: string): Boolean;
    function SetterRoutine(out ARoutine: TSyntaxNode; out AValue, AReason: string): Boolean;
    function NewSetter(const ABody: string; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
  end;

function TChangedTarget.Field: string;
begin
  Result := Accessor(Declaration, 'read');
  if Result = '' then
  begin
    Result := 'F' + Name;
  end;
end;

function TChangedTarget.Writer: string;
begin
  Result := Accessor(Declaration, 'write');
end;

/// <summary>Klasse an der Befehlszeile und ihre Property Name.</summary>
function TChangedTarget.Find(out AReason: string): Boolean;
begin
  if not Source.ClassAt(ClassSymbol) then
  begin
    Exit(Fail(cTexts[TComponentCommandsText.ChangedOnlyAppliesInA].Text, AReason));
  end;
  if not FindMember(Source, ClassSymbol, Name, [TIndexSymbolKind.Property_], Prop) then
  begin
    Exit(Fail(cTexts[TComponentCommandsText.HasNoProperty].Fmt([ClassSymbol.Name, Name]), AReason));
  end;
  Declaration := RangeText(Source.Lines, Prop.Range);
  Result := True;
end;

/// <summary>Rumpf des vorhandenen Setters (nil, wenn die Property ins Feld schreibt oder keinen Setter hat) und
/// der Name seines Parameters (sonst Value). False, wenn der Setter keinen Rumpf in der Datei hat.</summary>
function TChangedTarget.SetterRoutine(out ARoutine: TSyntaxNode; out AValue, AReason: string): Boolean;
var
  mWriter, mSignature: string;
begin
  ARoutine := nil;
  AValue := 'Value';
  Result := True;
  mWriter := Writer;
  if (mWriter = '') or SameText(mWriter, Field) then
  begin
    Exit;
  end;
  ARoutine := FindBody(Source, ClassSymbol.Name, mWriter);
  if ARoutine = nil then
  begin
    Exit(Fail(cTexts[TComponentCommandsText.BodyOfNotFound].Fmt([ClassSymbol.Name, mWriter]), AReason));
  end;
  mSignature := RoutineSignature(Source.Lines[ARoutine.StartPos.Line]);
  if ParameterNames(mSignature) <> '' then
  begin
    AValue := ParameterNames(mSignature);
  end;
end;

/// <summary>Ohne Setter: anlegen wie /prop und die Property darauf umstellen.</summary>
function TChangedTarget.NewSetter(const ABody: string; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mWriter, mNewDeclaration, mIndent, mLB: string;
begin
  AEdits := nil;
  if Prop.TypeName = '' then
  begin
    Exit(Fail(cTexts[TComponentCommandsText.TypeOfNotRecognized].Fmt([Name]), AReason));
  end;
  if Prop.Range.StartPos.Line <> Prop.Range.EndPos.Line then
  begin
    Exit(Fail(cTexts[TComponentCommandsText.MultiLinePropertyDeclarationPlease].Text, AReason));
  end;
  mWriter := 'Set' + Name;
  if Pos(' write ', Declaration) > 0 then
  begin
    mNewDeclaration := StringReplace(Declaration, ' write ' + Writer, ' write ' + mWriter, [rfIgnoreCase]);
  end
  else
  begin
    mNewDeclaration := StringReplace(Declaration, ';', ' write ' + mWriter + ';', []);
  end;
  mIndent := Source.Indent(ClassSymbol.Range.EndPos.Line);
  mLB := Source.LineBreak;
  AEdits := [TTextEdit.Create(Prop.Range, mNewDeclaration),
    Source.BeforeLine(ClassSymbol.Range.EndPos.Line, mIndent + 'private' + mLB + mIndent + '  ' +
    Format('procedure %s(const Value: %s);', [mWriter, Prop.TypeName])),
    Source.AddBody(ClassSymbol.Name, Format('procedure %s.%s(const Value: %s);', [ClassSymbol.Name, mWriter,
    Prop.TypeName]) + mLB + ABody), Source.RemoveCommand];
  Result := True;
end;

function ExecuteChanged(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mTarget: TChangedTarget;
  mCall, mValue, mBody: string;
  mRoutine, mBlock: TSyntaxNode;
begin
  AEdits := nil;
  mTarget := Default(TChangedTarget);
  mTarget.Name := Trim(AContext.Arguments);
  if not IsValidIdent(mTarget.Name) then
  begin
    Exit(Fail(cTexts[TComponentCommandsText.ExpectedIsChangedProperty].Text, AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    mTarget.Source := mSource;
    Result := mTarget.Find(AReason) and mTarget.SetterRoutine(mRoutine, mValue, AReason);
    if not Result then
    begin
      Exit;
    end;
    // Benachrichtigung: Invalidate bei Controls, sonst eine vorhandene Changed- bzw. DoChange-Methode; der Befehl
    // heißt "changed", deshalb ohne beide Changed.
    mCall := TSetterGenerator.NotifyCall(mSource, AContext.Index, mTarget.ClassSymbol);
    if mCall = '' then
    begin
      mCall := 'Changed';
    end;
    mBody := TSetterGenerator.Body(mTarget.Field, mValue, mCall, mSource.LineBreak);
    if mRoutine <> nil then
    begin
      mBlock := mRoutine.FindChild(TSyntaxKind.Block);
      AEdits := [TTextEdit.Create(TTextRange.Create(mBlock.StartPos.Line, 0, mBlock.EndPos.Line + 1, 0),
        mBody + mSource.LineBreak), mSource.RemoveCommand];
    end
    else
    begin
      Result := mTarget.NewSetter(mBody, AEdits, AReason);
    end;
  finally
    mSource.Free;
  end;
end;

{ /loaded }

function ExecuteLoaded(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mClassSymbol, mMember: TIndexSymbol;
  mLB: string;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    if not mSource.ClassAt(mClassSymbol) then
    begin
      Exit(Fail(cTexts[TComponentCommandsText.LoadedOnlyAppliesInA].Text, AReason));
    end;
    if not DescendsFrom(Ancestors(mSource, AContext.Index, mClassSymbol.Name), cComponentRoots) then
    begin
      Exit(Fail(cTexts[TComponentCommandsText.DoesNotDescendFromTComponent].Fmt([mClassSymbol.Name]),
        AReason));
    end;
    if FindMember(mSource, mClassSymbol, 'Loaded', [TIndexSymbolKind.Method], mMember) then
    begin
      Exit(Fail(cTexts[TComponentCommandsText.AlreadyHasLoaded].Fmt([mClassSymbol.Name]), AReason));
    end;
    mLB := mSource.LineBreak;
    AEdits := AddToClass(mSource, mClassSymbol, '', ['protected', 'procedure Loaded; override;']) +
      [mSource.AddBody(mClassSymbol.Name, Format('procedure %s.Loaded;', [mClassSymbol.Name]) + mLB + 'begin' + mLB +
      '  inherited Loaded;' + mLB + 'end;'), mSource.RemoveCommand];
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /notification }

/// <summary>Felder der Klasse mit Komponententyp bzw. ohne Argumente alle, sonst das genannte Feld.</summary>
function NotificationFields(ASource: TCommandSource; const AContext: TSlashContext;
  const AClassName: string): TArray<string>;
var
  mSymbol: TIndexSymbol;
  mWanted: string;
begin
  Result := nil;
  mWanted := Trim(AContext.Arguments);
  for mSymbol in ASource.UnitIndex.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Field) and SameText(mSymbol.Container, AClassName) and
      ((AContext.Arguments = '') and IsComponentType(ASource, AContext.Index, mSymbol.TypeName) or
      SameText(mSymbol.Name, mWanted)) then
    begin
      Result := Result + [mSymbol.Name];
    end;
  end;
end;

/// <summary>Zeilen der Routine ARoutine, je mit #10 abgeschlossen; '' ohne Routine.</summary>
function RoutineText(ASource: TCommandSource; ARoutine: TSyntaxNode): string;
var
  mIndex: Integer;
begin
  Result := '';
  if ARoutine = nil then
  begin
    Exit;
  end;
  for mIndex := ARoutine.StartPos.Line to ARoutine.EndPos.Line do
  begin
    Result := Result + ASource.Lines[mIndex] + #10;
  end;
end;

/// <summary>Bedingungen "if (Operation = opRemove) and (AComponent = F) then F := nil" für die Felder, die
/// ABodyText noch nicht behandelt.</summary>
function NotificationLines(const AFields: TArray<string>; const ABodyText: string): TArray<string>;
var
  mField, mCondition: string;
begin
  Result := nil;
  for mField in AFields do
  begin
    mCondition := Format('(AComponent = %s)', [mField]);
    if not ContainsText(ABodyText, mCondition) then
    begin
      Result := Result + [Format('  if (Operation = opRemove) and %s then', [mCondition]),
        Format('    %s := nil;', [mField])];
    end;
  end;
end;

/// <summary>ALines vor das end der vorhandenen Notification bzw. eine neue Notification.</summary>
function NotificationEdits(ASource: TCommandSource; const AClass: TIndexSymbol; ARoutine: TSyntaxNode;
  const ALines: TArray<string>): TArray<TTextEdit>;
var
  mLB: string;
begin
  mLB := ASource.LineBreak;
  if ARoutine <> nil then
  begin
    Result := [ASource.BeforeLine(ARoutine.FindChild(TSyntaxKind.Block).EndPos.Line, string.Join(mLB, ALines))];
  end
  else
  begin
    Result := AddToClass(ASource, AClass, '', ['protected',
      'procedure Notification(AComponent: TComponent; Operation: TOperation); override;']) +
      [ASource.AddBody(AClass.Name, Format('procedure %s.Notification(AComponent: TComponent; ' +
      'Operation: TOperation);', [AClass.Name]) + mLB + 'begin' + mLB +
      '  inherited Notification(AComponent, Operation);' + mLB + string.Join(mLB, ALines) + mLB + 'end;')];
  end;
end;

/// <summary>Der Setter von AProp meldet sich beim neuen Wert an und beim alten ab, wenn die Property eines der
/// Felder AFields liest und der Setter das noch nicht tut; sonst leer.</summary>
function SetterNotificationEdits(ASource: TCommandSource; const AClassName: string; const AProp: TIndexSymbol;
  const AFields: TArray<string>): TArray<TTextEdit>;
var
  mDeclaration, mField, mSetter, mLB: string;
  mRoutine, mBlock: TSyntaxNode;
begin
  Result := nil;
  mDeclaration := RangeText(ASource.Lines, AProp.Range);
  mField := Accessor(mDeclaration, 'read');
  mSetter := Accessor(mDeclaration, 'write');
  if (IndexText(mField, AFields) < 0) or (mSetter = '') or SameText(mSetter, mField) then
  begin
    Exit;
  end;
  mRoutine := FindBody(ASource, AClassName, mSetter);
  if (mRoutine = nil) or ContainsText(RoutineText(ASource, mRoutine), 'FreeNotification') then
  begin
    Exit;
  end;
  mBlock := mRoutine.FindChild(TSyntaxKind.Block);
  mLB := ASource.LineBreak;
  Result := [ASource.AfterLine(mBlock.StartPos.Line, Format('  if %s <> nil then', [mField]) + mLB +
    Format('    %s.RemoveFreeNotification(Self);', [mField])), ASource.BeforeLine(mBlock.EndPos.Line,
    Format('  if %s <> nil then', [mField]) + mLB + Format('    %s.FreeNotification(Self);', [mField]))];
end;

/// <summary>Setter der Properties zu AFields melden sich beim neuen Wert an und beim alten ab.</summary>
function FreeNotificationEdits(ASource: TCommandSource; const AClassName: string;
  const AFields: TArray<string>): TArray<TTextEdit>;
var
  mSymbol: TIndexSymbol;
begin
  Result := nil;
  for mSymbol in ASource.UnitIndex.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Property_) and SameText(mSymbol.Container, AClassName) then
    begin
      Result := Result + SetterNotificationEdits(ASource, AClassName, mSymbol, AFields);
    end;
  end;
end;

/// <summary>Klasse unter dem Cursor und ihre Komponentenfelder für /notification; sonst der Grund, warum der
/// Befehl hier nicht passt.</summary>
function NotificationTarget(ASource: TCommandSource; const AContext: TSlashContext; out AClass: TIndexSymbol;
  out AFields: TArray<string>): string;
begin
  Result := '';
  AFields := nil;
  if not ASource.ClassAt(AClass) then
  begin
    Result := cTexts[TComponentCommandsText.NotificationOnlyAppliesInA].Text;
  end
  else if not DescendsFrom(Ancestors(ASource, AContext.Index, AClass.Name), cComponentRoots) then
  begin
    Result := cTexts[TComponentCommandsText.DoesNotDescendFromTComponent2].Fmt([AClass.Name]);
  end
  else
  begin
    AFields := NotificationFields(ASource, AContext, AClass.Name);
    if (AFields = nil) and (AContext.Arguments = '') then
    begin
      Result := cTexts[TComponentCommandsText.NoFieldsWithAComponent].Text;
    end
    else if AFields = nil then
    begin
      Result := cTexts[TComponentCommandsText.HasNoField].Fmt([AClass.Name, AContext.Arguments]);
    end;
  end;
end;

function ExecuteNotification(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mClass: TIndexSymbol;
  mFields, mLines: TArray<string>;
  mRoutine: TSyntaxNode;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    AReason := NotificationTarget(mSource, AContext, mClass, mFields);
    if AReason <> '' then
    begin
      Exit(False);
    end;
    // Vorhandene Bedingungen nicht verdoppeln.
    mRoutine := FindBody(mSource, mClass.Name, 'Notification');
    mLines := NotificationLines(mFields, RoutineText(mSource, mRoutine));
    if mLines = nil then
    begin
      Exit(Fail(cTexts[TComponentCommandsText.NotificationAlreadyHandlesTheseFields].Text, AReason));
    end;
    AEdits := NotificationEdits(mSource, mClass, mRoutine, mLines) +
      FreeNotificationEdits(mSource, mClass.Name, mFields) + [mSource.RemoveCommand];
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /event }

/// <summary>Zeile, vor der ein Handler in den ersten (published) Abschnitt des Formulars kommt: die erste
/// Sichtbarkeitszeile, sonst das "end" der Klasse.</summary>
function HandlerLine(ASource: TCommandSource; const AClass: TIndexSymbol): Integer;
var
  mLine: Integer;
  mWord: string;
begin
  for mLine := AClass.Range.StartPos.Line + 1 to AClass.Range.EndPos.Line - 1 do
  begin
    mWord := LowerCase(Trim(ASource.Lines[mLine]));
    if (mWord = 'private') or (mWord = 'protected') or (mWord = 'public') or (mWord = 'published') or
      StartsStr('strict ', mWord) then
    begin
      Exit(mLine);
    end;
  end;
  Result := AClass.Range.EndPos.Line;
end;

/// <summary>Objekt AName in AObject oder darunter; nil ohne.</summary>
function FindDfmObject(AObject: TDfmObject; const AName: string): TDfmObject;
var
  mChild: TDfmObject;
begin
  if SameText(AObject.Name, AName) then
  begin
    Exit(AObject);
  end;
  for mChild in AObject.Children do
  begin
    Result := FindDfmObject(mChild, AName);
    if Result <> nil then
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

/// <summary>Einrückung der Zeile ALine in ALines.</summary>
function LineIndent(const ALines: TArray<string>; ALine: Integer): string;
begin
  Result := '';
  if (ALine >= 0) and (ALine <= High(ALines)) then
  begin
    Result := Copy(ALines[ALine], 1, Length(ALines[ALine]) - Length(TrimLeft(ALines[ALine])));
  end;
end;

/// <summary>"/event Komponente.OnX" bzw. "/event OnX" zerlegen; False bei falscher Form.</summary>
function ParseEventArguments(const AArguments: string; out AComponent, AEvent: string): Boolean;
var
  mDot: Integer;
begin
  mDot := Pos('.', AArguments);
  AComponent := '';
  AEvent := Trim(AArguments);
  if mDot > 0 then
  begin
    AComponent := Trim(Copy(AArguments, 1, mDot - 1));
    AEvent := Trim(Copy(AArguments, mDot + 1, MaxInt));
  end;
  Result := ((AComponent = '') or IsValidIdent(AComponent)) and IsValidIdent(AEvent) and
    StartsText('On', AEvent) and (Length(AEvent) >= 3);
end;

type
  /// <summary>Ablauf von /event: Handler im Formular anlegen und in der Formulardatei zuweisen.</summary>
  TEventPlan = record
    Source: TCommandSource;
    ClassSymbol: TIndexSymbol;
    Arguments: string;
    /// <summary>Komponente vor dem Punkt; '' für das Formular selbst.</summary>
    Component: string;
    Event: string;
    /// <summary>Typ der Komponente, ohne Komponente die Klasse selbst.</summary>
    ComponentType: string;
    /// <summary>Pfad der Unit; '' ohne URI.</summary>
    FileName: string;
    /// <summary>Signatur des Ereignistyps.</summary>
    Kind: string;
    Params: string;
    ResultType: string;
    Handler: string;
    /// <summary>Formulardatei und ihr neuer Text mit der Zuweisung.</summary>
    FormFile: string;
    NewForm: string;
    function FindComponentType(out AReason: string): Boolean;
    function ReadEventType(const AContext: TSlashContext; out ATypeName: string): Boolean;
    function ReadSignature(const AContext: TSlashContext; out AReason: string): Boolean;
    function HandlerBase(const AContext: TSlashContext): string;
    procedure ChooseHandler(const AContext: TSlashContext);
    function ReadForm(const AContext: TSlashContext; out AFormText, AReason: string): Boolean;
    function FormTarget(ADocument: TDfmDocument; out ATarget: TDfmObject; out AReason: string): Boolean;
    function AssignInForm(const AFormText: string; out AReason: string): Boolean;
    function Prepare(const AContext: TSlashContext; out AReason: string): Boolean;
    function HandlerEdits: TArray<TTextEdit>;
  end;

/// <summary>Typ der Komponente: Feld der Klasse, ohne Komponente die Klasse selbst.</summary>
function TEventPlan.FindComponentType(out AReason: string): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  Result := True;
  ComponentType := ClassSymbol.Name;
  if Component = '' then
  begin
    Exit;
  end;
  ComponentType := '';
  for mSymbol in Source.UnitIndex.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Field) and SameText(mSymbol.Container, ClassSymbol.Name) and
      SameText(mSymbol.Name, Component) then
    begin
      ComponentType := mSymbol.TypeName;
    end;
  end;
  if ComponentType = '' then
  begin
    Result := Fail(cTexts[TComponentCommandsText.HasNoField].Fmt([ClassSymbol.Name, Component]), AReason);
  end;
end;

/// <summary>Typ der Ereignis-Property Event von ComponentType über den Namensauflöser; False ohne.</summary>
function TEventPlan.ReadEventType(const AContext: TSlashContext; out ATypeName: string): Boolean;
var
  mOwn: TUnitIndex;
  mResolver: TNameResolver;
  mType, mEvent: TResolvedSymbol;
begin
  ATypeName := '';
  mOwn := Source.UnitIndex;
  mOwn.FileName := FileName;
  mResolver := TNameResolver.Create(AContext.Index);
  try
    mResolver.Namespaces := AContext.Namespaces;
    Result := mResolver.ResolveNameFrom(mOwn, ComponentType, mType) and
      mResolver.DeclaredMember(mType, Event, mEvent) and (mEvent.SymbolKind = TIndexSymbolKind.Property_) and
      (mEvent.TypeName <> '');
    if Result then
    begin
      ATypeName := mEvent.TypeName;
    end;
  finally
    mResolver.Free;
  end;
end;

function TEventPlan.ReadSignature(const AContext: TSlashContext; out AReason: string): Boolean;
var
  mTypeName: string;
  mChain: TArray<string>;
begin
  if not ReadEventType(AContext, mTypeName) then
  begin
    Exit(Fail(cTexts[TComponentCommandsText.HasNoEvent].Fmt([ComponentType, Event]), AReason));
  end;
  mChain := mTypeName.Split(['.']);
  if not EventSignature(Source, AContext.Index, mChain[High(mChain)], Kind, Params, ResultType) then
  begin
    Exit(Fail(cTexts[TComponentCommandsText.EventTypeNotFoundProcedure].Fmt([mTypeName]), AReason));
  end;
  Result := True;
end;

/// <summary>Name wie in der IDE: Button1Click, für das Formular selbst FormCreate.</summary>
function TEventPlan.HandlerBase(const AContext: TSlashContext): string;
var
  mAncestors: TArray<string>;
begin
  mAncestors := Ancestors(Source, AContext.Index, ClassSymbol.Name);
  if Component <> '' then
  begin
    Result := Component;
  end
  else if DescendsFrom(mAncestors, ['TDataModule']) then
  begin
    Result := 'DataModule';
  end
  else if DescendsFrom(mAncestors, ['TFrame']) then
  begin
    Result := 'Frame';
  end
  else
  begin
    Result := 'Form';
  end;
  Result := Result + Copy(Event, 3, MaxInt);
end;

/// <summary>Freier Handlername: HandlerBase, bei Namensgleichheit mit einer Methode mit Nummer.</summary>
procedure TEventPlan.ChooseHandler(const AContext: TSlashContext);
var
  mBase: string;
  mNumber: Integer;
  mExisting: TIndexSymbol;
begin
  mBase := HandlerBase(AContext);
  Handler := mBase;
  mNumber := 1;
  while FindMember(Source, ClassSymbol, Handler, [TIndexSymbolKind.Method], mExisting) do
  begin
    Inc(mNumber);
    Handler := mBase + IntToStr(mNumber);
  end;
end;

/// <summary>Formulardatei neben der Unit: .dfm, sonst .fmx.</summary>
function TEventPlan.ReadForm(const AContext: TSlashContext; out AFormText, AReason: string): Boolean;
var
  mExtension: string;
begin
  FormFile := '';
  AFormText := '';
  if FileName <> '' then
  begin
    for mExtension in TArray<string>.Create('.dfm', '.fmx') do
    begin
      if (FormFile = '') and AContext.Host.ReadFile(ChangeFileExt(FileName, mExtension), AFormText) then
      begin
        FormFile := ChangeFileExt(FileName, mExtension);
      end;
    end;
  end;
  Result := FormFile <> '';
  if not Result then
  begin
    Result := Fail(cTexts[TComponentCommandsText.ThereIsNoDfmOr].Text, AReason);
  end;
end;

/// <summary>Objekt der Komponente in der Formulardatei, dem Event noch nicht zugewiesen ist.</summary>
function TEventPlan.FormTarget(ADocument: TDfmDocument; out ATarget: TDfmObject; out AReason: string): Boolean;
var
  mProp: TDfmProperty;
begin
  ATarget := nil;
  if ADocument.Root = nil then
  begin
    Exit(Fail(cTexts[TComponentCommandsText.IsNotATextDFM].Fmt([ExtractFileName(FormFile)]), AReason));
  end;
  ATarget := ADocument.Root;
  if Component <> '' then
  begin
    ATarget := FindDfmObject(ADocument.Root, Component);
  end;
  if ATarget = nil then
  begin
    Exit(Fail(cTexts[TComponentCommandsText.IsNotIn].Fmt([Component, ExtractFileName(FormFile)]), AReason));
  end;
  for mProp in ATarget.Properties do
  begin
    if SameText(mProp.Name, Event) then
    begin
      Exit(Fail(cTexts[TComponentCommandsText.IsAlreadyAssignedTo].Fmt([Arguments, Trim(mProp.Value)]), AReason));
    end;
  end;
  Result := True;
end;

/// <summary>"Event = Handler" hinter die letzte Eigenschaft des Objekts, ohne Eigenschaften hinter seine
/// Kopfzeile; setzt NewForm.</summary>
function TEventPlan.AssignInForm(const AFormText: string; out AReason: string): Boolean;
var
  mDocument: TDfmDocument;
  mTarget: TDfmObject;
  mLines: TArray<string>;
  mLB: string;
  mLine: Integer;
  mProp: TDfmProperty;
begin
  mDocument := TDfmParser.Parse(AFormText);
  try
    Result := FormTarget(mDocument, mTarget, AReason);
    if not Result then
    begin
      Exit;
    end;
    mLines := TTextLines.SplitLines(AFormText, mLB);
    mLine := mTarget.Range.StartPos.Line;
    for mProp in mTarget.Properties do
    begin
      if mProp.ValueRange.EndPos.Line > mLine then
      begin
        mLine := mProp.ValueRange.EndPos.Line;
      end;
    end;
    Insert(LineIndent(mLines, mTarget.Range.StartPos.Line) + '  ' + Event + ' = ' + Handler, mLines, mLine + 1);
    NewForm := TTextLines.JoinLines(mLines, mLB);
  finally
    mDocument.Free;
  end;
end;

/// <summary>Klasse, Ereignistyp, Handlername und Zuweisung in der Formulardatei ermitteln.</summary>
function TEventPlan.Prepare(const AContext: TSlashContext; out AReason: string): Boolean;
var
  mFormText: string;
begin
  if not Source.ClassAt(ClassSymbol) then
  begin
    Exit(Fail(cTexts[TComponentCommandsText.EventOnlyAppliesInA].Text, AReason));
  end;
  Result := FindComponentType(AReason) and ReadSignature(AContext, AReason);
  if Result then
  begin
    ChooseHandler(AContext);
    Result := ReadForm(AContext, mFormText, AReason) and AssignInForm(mFormText, AReason);
  end;
end;

/// <summary>Deklaration des Handlers im ersten Abschnitt und sein leerer Rumpf.</summary>
function TEventPlan.HandlerEdits: TArray<TTextEdit>;
var
  mHeader, mBody, mLB: string;
  mEdit: TTextEdit;
begin
  mLB := Source.LineBreak;
  mHeader := Handler;
  if Params <> '' then
  begin
    mHeader := mHeader + '(' + Params + ')';
  end;
  if ResultType <> '' then
  begin
    mHeader := mHeader + ': ' + ResultType;
  end;
  mBody := Kind + ' ' + ClassSymbol.Name + '.' + mHeader + ';' + mLB + 'begin' + mLB + mLB + 'end;';
  Result := [Source.BeforeLine(HandlerLine(Source, ClassSymbol), Source.Indent(ClassSymbol.Range.EndPos.Line) +
    '  ' + Kind + ' ' + mHeader + ';')];
  if TClassCompletion.BodyEdit(Source.Tree, Source.Text, ClassSymbol.Name, mBody, mEdit) then
  begin
    Result := Result + [mEdit];
  end
  else
  begin
    Result := Result + [Source.AddBody(ClassSymbol.Name, mBody)];
  end;
  Result := Result + [Source.RemoveCommand];
end;

/// <summary>Die Formulardatei erst schreiben, wenn die Änderungen an der Unit übernommen sind.</summary>
procedure DeferFormWrite(const AContext: TSlashContext; const AFormFile, ANewForm: string);
var
  mHost: ISlashHost;
  mUri, mFile, mForm: string;
begin
  mHost := AContext.Host;
  mUri := AContext.Uri;
  mFile := AFormFile;
  mForm := ANewForm;
  AContext.Defer(
    procedure
    begin
      mHost.WriteFiles(mUri, [TSlashFile.Create(mFile, mForm, False)], '');
    end);
end;

function ExecuteEvent(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mPlan: TEventPlan;
begin
  AEdits := nil;
  mPlan := Default(TEventPlan);
  mPlan.Arguments := AContext.Arguments;
  if not ParseEventArguments(AContext.Arguments, mPlan.Component, mPlan.Event) then
  begin
    Exit(Fail(cTexts[TComponentCommandsText.ExpectedIsEventButton1OnClick].Text, AReason));
  end;
  if AContext.Host = nil then
  begin
    Exit(Fail(cTexts[TComponentCommandsText.EventNeedsTheEditor].Text, AReason));
  end;
  if AContext.Uri <> '' then
  begin
    mPlan.FileName := TDocumentUris.ToPath(AContext.Uri);
  end;
  mSource := TCommandSource.Create(AContext);
  try
    mPlan.Source := mSource;
    Result := mPlan.Prepare(AContext, AReason);
    if Result then
    begin
      AEdits := mPlan.HandlerEdits;
    end;
  finally
    mSource.Free;
  end;
  if Result then
  begin
    DeferFormWrite(AContext, mPlan.FormFile, mPlan.NewForm);
  end;
end;

function Command(const AName, ASummary, AExample: string; const AExecute: TSlashExecute): TSlashCommand;
begin
  Result.Name := AName;
  Result.Summary := ASummary;
  Result.Example := AExample;
  Result.Execute := AExecute;
end;

procedure RegisterComponentCommands(const ARegister: TSlashRegister);
begin
  ARegister(Command('notify', cTexts[TComponentCommandsText.EventWithFieldPropertyAnd].Text, '/notify OnChange',
    ExecuteNotify));
  ARegister(Command('changed', cTexts[TComponentCommandsText.SetterWithChangeCheckAnd].Text,
    cTexts[TComponentCommandsText.ChangedColor].Text,
    ExecuteChanged));
  ARegister(Command('loaded', cTexts[TComponentCommandsText.OverrideLoaded].Text, '/loaded', ExecuteLoaded));
  ARegister(Command('event', cTexts[TComponentCommandsText.CreateAnEventHandlerAnd].Text, '/event Button1.OnClick',
    ExecuteEvent));
  ARegister(Command('notification', cTexts[TComponentCommandsText.NotificationForComponentFields].Text,
    '/notification FDataSource',
    ExecuteNotification));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.ComponentCommands', cTexts);

end.
