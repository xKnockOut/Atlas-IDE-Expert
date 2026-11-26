unit Atlas.Common.Editing.Completion.Declare;

// Unbekannte Namen deklarieren (#471): Am unbekannten Namen im Rumpf einer Routine bietet die Vervollständigung
// lokale Variable (auch als Inline-Variable), Feld der Klasse und Konstante an. Editing meldet die Quelle an der
// Stelle TCompletionSlot.Declare an; die Einträge kommen ans Ende der Liste.

interface

uses
  Atlas.Common.Completion.Contract,
  Atlas.Common.Completion.Request,
  Atlas.Common.Completion.Answer;

type
  TEditingDeclareCompletion = class
  public
    /// <summary>Unbekannter Name am Cursor im Rumpf einer Routine: lokale Variable (mit ARequest.InlineVar auch
    /// als Inline-var), Feld der Klasse (F-Konvention, die Verwendung wird umbenannt) und, wenn der Name als Wert
    /// dient, Konstante in der implementation. Typ aus der rechten Seite einer Zuweisung, sonst aus dem
    /// erwarteten Typ, sonst ein Platzhalter. False, wenn der Name bekannt ist oder in AKnown genau vorkommt.
    /// </summary>
    class function Items(ARequest: TCompletionRequest; const AKnown: TArray<TCompletionItem>;
      out AItems: TArray<TCompletionItem>): Boolean; static;
    /// <summary>Quelle für TCompletionSlot.Declare: hängt die Einträge an den Schluss der Antwort, die dann
    /// unvollständig ist (der Name ändert sich beim Weitertippen).</summary>
    class function Source: TCompletionSource; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclareUnknown,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.ExpectedTypes,
  Atlas.Common.Semantics.TypeImports,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Texte der Deklarieren-Einträge in beiden Sprachen (#1458).</summary>
  TDeclareText = (CreateALocalVariable, CreateInlineVariable, CreateField, CreateConstant);

const
  cTexts: array[TDeclareText] of TAtlasText = (
    (De: 'Lokale Variable anlegen'; En: 'Create a local variable'),
    (De: 'Inline-Variable anlegen'; En: 'Create inline variable'),
    (De: 'Feld %s anlegen'; En: 'Create field %s'),
    (De: 'Konstante anlegen'; En: 'Create constant'));

type
  /// <summary>Baut die Einträge von TEditingDeclareCompletion.Items (#471) für einen unbekannten Namen.</summary>
  TDeclareBuilder = class
  private
    FRequest: TCompletionRequest;
    FSlot: TUnknownSlot;
    FSource: TCommandSource;
    FRoutine: TSyntaxNode;
    FTypeName: string;
    FDeclType: string;
    FBase: TCompletionItem;
    function TypeEdits(AOffset: Integer): TArray<TTextEdit>;
    function ClassFields(const AClass: TIndexSymbol): TArray<string>;
    function FieldEdit(const AClass: TIndexSymbol; const AField: string): TTextEdit;
    function ConstantEdit(const ADetail: string): TTextEdit;
  public
    Items: TArray<TCompletionItem>;
    constructor Create(ARequest: TCompletionRequest; const ASlot: TUnknownSlot; ASource: TCommandSource;
      ARoutine: TSyntaxNode);
    procedure AddLocal(AInlineVar: Boolean);
    procedure AddField;
    procedure AddConstant;
  end;

/// <summary>Typ eines aufgelösten Ausdrucksteils: Konstruktor → Klasse, Typumwandlung → Typ, sonst sein Typ.</summary>
function TypeOfResolved(const ASymbol: TResolvedSymbol): string;
begin
  Result := '';
  if not ASymbol.Found or (ASymbol.Kind = TResolvedKind.UnitName) then
  begin
    Exit;
  end;
  if ASymbol.SymbolKind = TIndexSymbolKind.Constructor_ then
  begin
    Result := ASymbol.Container;
  end
  else if ASymbol.IsType then
  begin
    Result := ASymbol.Name;
  end
  else if ASymbol.TypeName <> '' then
  begin
    Result := ASymbol.TypeName;
  end
  else if ASymbol.SymbolKind = TIndexSymbolKind.EnumMember then
  begin
    Result := ASymbol.Container;
  end;
end;

/// <summary>Typ für den unbekannten Namen: rechte Seite der Zuweisung, sonst der erwartete Typ.</summary>
function SlotType(ARequest: TCompletionRequest; const ASlot: TUnknownSlot): string;
var
  mTermFirst, mTermLast, mNameToken: Integer;
  mTokens: TArray<TPascalToken>;
begin
  if not ASlot.AssignTarget then
  begin
    Exit(TExpectedTypes.At(ARequest.Resolver, ARequest.Tree, ARequest.FileName, ARequest.Position));
  end;
  mTokens := ARequest.Tree.Tokens;
  Result := TDeclareUnknown.Shape(mTokens, ASlot.ValueFirst, ASlot.ValueLast, mTermFirst, mTermLast);
  if (Result = '') and (mTermFirst >= 0) and (mTermFirst = mTermLast) then
  begin
    Result := TDeclareUnknown.LiteralType(mTokens[mTermFirst]);
  end;
  if (Result = '') and (mTermFirst >= 0) then
  begin
    mNameToken := TDeclareUnknown.TermName(mTokens, mTermFirst, mTermLast);
    if mNameToken >= 0 then
    begin
      Result := TypeOfResolved(ARequest.Resolver.Resolve(ARequest.Tree, ARequest.FileName,
        mTokens[mNameToken].StartPos));
    end;
  end;
end;

/// <summary>Ist der Name bekannt: ein Eintrag passt genau oder die Namensauflösung findet ihn?</summary>
function IsKnownName(ARequest: TCompletionRequest; const ASlot: TUnknownSlot;
  const AKnown: TArray<TCompletionItem>): Boolean;
var
  mKnown: TCompletionItem;
begin
  for mKnown in AKnown do
  begin
    if SameText(mKnown.Name, ASlot.Name) then
    begin
      Exit(True);
    end;
  end;
  Result := ARequest.Resolver.Resolve(ARequest.Tree, ARequest.FileName, ASlot.NameRange.StartPos).Found;
end;

/// <summary>Quelle der Befehle für die Zeile des Cursors.</summary>
function CommandSourceFor(ARequest: TCompletionRequest): TCommandSource;
var
  mSlash: TSlashContext;
begin
  mSlash := Default(TSlashContext);
  mSlash.Text := ARequest.Text;
  mSlash.Line := ARequest.Position.Line;
  mSlash.LineText := ARequest.LineText(ARequest.Position.Line);
  Result := TCommandSource.Create(mSlash);
end;

{ TDeclareBuilder }

constructor TDeclareBuilder.Create(ARequest: TCompletionRequest; const ASlot: TUnknownSlot; ASource: TCommandSource;
  ARoutine: TSyntaxNode);
begin
  inherited Create;
  FRequest := ARequest;
  FSlot := ASlot;
  FSource := ASource;
  FRoutine := ARoutine;
  FTypeName := SlotType(ARequest, ASlot);
  FDeclType := FTypeName;
  if FDeclType = '' then
  begin
    FDeclType := TDeclareUnknown.cTypePlaceholder;
  end;
  FBase := Default(TCompletionItem);
  FBase.Action := 'declare';
  FBase.Unknown := ASlot.Name;
  FBase.HasTextEdit := True;
end;

function TDeclareBuilder.TypeEdits(AOffset: Integer): TArray<TTextEdit>;
begin
  Result := TTypeImports.Edits(FRequest.Resolver, FRequest.Index, FRequest.Tree, FRequest.FileName, FTypeName,
    FSource.LineBreak, AOffset);
end;

function TDeclareBuilder.ClassFields(const AClass: TIndexSymbol): TArray<string>;
var
  mSymbol: TIndexSymbol;
begin
  Result := nil;
  for mSymbol in FSource.UnitIndex.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Field) and (SameText(mSymbol.Container, AClass.QualifiedName) or
      SameText(mSymbol.Container, AClass.Name)) then
    begin
      Result := Result + [mSymbol.Name];
    end;
  end;
end;

function TDeclareBuilder.FieldEdit(const AClass: TIndexSymbol; const AField: string): TTextEdit;
var
  mLine, mEnd: Integer;
  mDeclaration: string;
begin
  mDeclaration := Format('%s: %s;', [AField, FDeclType]);
  mLine := FSource.PrivateLine(AClass);
  if mLine >= 0 then
  begin
    Exit(FSource.AfterLine(mLine, FSource.Indent(mLine) + '  ' + mDeclaration));
  end;
  mEnd := AClass.Range.EndPos.Line;
  Result := FSource.BeforeLine(mEnd, FSource.Indent(mEnd) + 'private' + FSource.LineBreak + FSource.Indent(mEnd) +
    '  ' + mDeclaration);
end;

function TDeclareBuilder.ConstantEdit(const ADetail: string): TTextEdit;
var
  mSection, mNode: TSyntaxNode;
  mIndex: Integer;
begin
  mSection := FSource.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
  mNode := nil;
  if mSection <> nil then
  begin
    for mIndex := 0 to mSection.ChildCount - 1 do
    begin
      if (mSection[mIndex].Kind = TSyntaxKind.ConstSection) and (mNode = nil) then
      begin
        mNode := mSection[mIndex];
      end;
    end;
  end;
  if mNode <> nil then
  begin
    Result := FSource.AfterLine(mNode.EndPos.Line, '  ' + ADetail);
  end
  else
  begin
    Result := FSource.AfterLine(FSource.ImplementationStart, FSource.LineBreak + 'const' + FSource.LineBreak + '  ' +
      ADetail);
  end;
end;

procedure TDeclareBuilder.AddLocal(AInlineVar: Boolean);
var
  mItem: TCompletionItem;
begin
  // Lokale Variable im var-Abschnitt; der Cursor bleibt im Namen.
  mItem := FBase;
  mItem.Name := cTexts[TDeclareText.CreateALocalVariable].Text;
  mItem.Kind := cKindVariable;
  mItem.Detail := Format('%s: %s', [FSlot.Name, FDeclType]);
  mItem.TextEdit := TTextEdit.Create(FSlot.NameRange, TDeclareUnknown.WithCaret(FSlot.Name, FSlot.CursorOffset));
  mItem.AdditionalEdits := [Atlas.Common.Editing.CommandSource.AddLocal(FSource, FRoutine, TSyntaxKind.VarSection,
    'var', Format('%s: %s;', [FSlot.Name, FDeclType]))] + TypeEdits(FRoutine.StartOffset);
  Items := Items + [mItem];
  // Inline-Variable an der Stelle (ab Delphi 10.3): Den Typ leitet der Compiler ab.
  if AInlineVar and FSlot.InlineAllowed then
  begin
    mItem := FBase;
    mItem.Name := cTexts[TDeclareText.CreateInlineVariable].Text;
    mItem.Kind := cKindVariable;
    mItem.Detail := Format('var %s := …', [FSlot.Name]);
    mItem.TextEdit := TTextEdit.Create(FSlot.NameRange, TDeclareUnknown.WithCaret('var ' + FSlot.Name,
      FSlot.CursorOffset + 4));
    Items := Items + [mItem];
  end;
end;

procedure TDeclareBuilder.AddField;
var
  mClass: TIndexSymbol;
  mFields: TArray<string>;
  mField: string;
  mItem: TCompletionItem;
begin
  // Feld im private-Abschnitt der Klasse, wenn die Routine eine ihrer Methoden ist.
  if (Pos('.', FRoutine.Name) = 0) or not FSource.ClassAt(mClass) then
  begin
    Exit;
  end;
  mFields := ClassFields(mClass);
  mField := TDeclareUnknown.FieldName(FSlot.Name, TDeclareUnknown.UsesFieldPrefix(mFields));
  if MatchText(mField, mFields) then
  begin
    Exit;
  end;
  mItem := FBase;
  mItem.Name := cTexts[TDeclareText.CreateField].Fmt([mField]);
  mItem.Kind := cKindField;
  mItem.Detail := Format('%s: %s', [mField, FDeclType]);
  // Die Verwendung heißt danach wie das Feld; der Cursor bleibt an derselben Stelle im Namen.
  mItem.TextEdit := TTextEdit.Create(FSlot.NameRange, TDeclareUnknown.WithCaret(mField,
    FSlot.CursorOffset + Length(mField) - Length(FSlot.Name)));
  mItem.AdditionalEdits := [FieldEdit(mClass, mField)] + TypeEdits(FSource.Offset(mClass.Range.StartPos.Line));
  Items := Items + [mItem];
end;

procedure TDeclareBuilder.AddConstant;
var
  mItem: TCompletionItem;
begin
  // Konstante in der implementation, wenn der Name als Wert dient; der Wert ist ein Platzhalter.
  if FSlot.AssignTarget or (FSource.ImplementationStart < 0) then
  begin
    Exit;
  end;
  mItem := FBase;
  mItem.Name := cTexts[TDeclareText.CreateConstant].Text;
  mItem.Kind := cKindConstant;
  mItem.Detail := Format('%s = %s;', [FSlot.Name, TDeclareUnknown.DefaultValue(FTypeName)]);
  mItem.TextEdit := TTextEdit.Create(FSlot.NameRange, TDeclareUnknown.WithCaret(FSlot.Name, FSlot.CursorOffset));
  mItem.AdditionalEdits := [ConstantEdit(mItem.Detail)];
  Items := Items + [mItem];
end;

{ TEditingDeclareCompletion }

class function TEditingDeclareCompletion.Items(ARequest: TCompletionRequest; const AKnown: TArray<TCompletionItem>;
  out AItems: TArray<TCompletionItem>): Boolean;
var
  mSlot: TUnknownSlot;
  mSource: TCommandSource;
  mBuilder: TDeclareBuilder;
begin
  AItems := nil;
  if (ARequest.Tree = nil) or not TDeclareUnknown.Slot(ARequest.Tree.Tokens, ARequest.Position, mSlot) or
    IsKnownName(ARequest, mSlot, AKnown) then
  begin
    Exit(False);
  end;
  mSource := CommandSourceFor(ARequest);
  try
    // Nur im Rumpf einer Routine: dort sind Variablen, Felder und Konstanten Deklarationen wert.
    if mSource.RoutineAt <> nil then
    begin
      mBuilder := TDeclareBuilder.Create(ARequest, mSlot, mSource, mSource.RoutineAt);
      try
        mBuilder.AddLocal(ARequest.InlineVar);
        mBuilder.AddField;
        mBuilder.AddConstant;
        AItems := mBuilder.Items;
      finally
        mBuilder.Free;
      end;
    end;
  finally
    mSource.Free;
  end;
  Result := AItems <> nil;
end;

class function TEditingDeclareCompletion.Source: TCompletionSource;
begin
  Result :=
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    var
      mDeclares: TArray<TCompletionItem>;
    begin
      Result := TCompletionOutcome.Next;
      if Items(ARequest, AAnswer.Prefetched + AAnswer.Body + AAnswer.Tail, mDeclares) then
      begin
        AAnswer.Tail := AAnswer.Tail + mDeclares;
        AAnswer.Incomplete := True;
      end;
    end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.Completion.Declare', cTexts);

end.
