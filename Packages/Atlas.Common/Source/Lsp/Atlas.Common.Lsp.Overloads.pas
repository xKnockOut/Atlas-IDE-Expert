unit Atlas.Common.Lsp.Overloads;

// Überladung anlegen über das Protokoll (#674):
//   - Code-Aktionen auf dem Kopf einer Routine: „Überladung anlegen (als
//     Weiterleitung)“ und „Überladung anlegen (Kopie)“, je mit dem
//     Client-Befehl atlas.createOverload [uri, position, art] (art = forward
//     bzw. copy). Geht es nicht, ist die Aktion abgeschaltet und nennt den
//     Grund.
//   - Befehl atlas.server.createOverload [uri, position, art]:
//     {"edit": WorkspaceEdit, "placeholders": [{"number", "range"}],
//     "warnings": [...]}. Die Platzhalter liegen im Text nach den Änderungen;
//     gleiche Nummern sind verknüpft, 0 ist die Endposition. Geht es nicht,
//     ein Fehler mit Grund.
//   - Den Standardwert eines weggelassenen Parameters liefert die
//     Namensauflösung: nil bei Klassen und Interfaces, das erste Element bei
//     Aufzählungen; sonst die eingebaute Regel bzw. Default(Typ).

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.Overloads;

type
  TLspOverloads = class
  public const
    cClientCommand = 'atlas.createOverload';
    cApplyCommand = 'atlas.server.createOverload';
    cActionKind = 'refactor.rewrite';
    cCopyName = 'copy';
    cForwardName = 'forward';
  public
    class function KindName(AKind: TOverloadKind): string; static;
    class function KindOf(const AName: string; out AKind: TOverloadKind): Boolean; static;
    /// <summary>Die Code-Aktionen an APosition. Der Aufrufer übernimmt die Objekte.</summary>
    class function Actions(ATree: TSyntaxTree; const AText, AUri: string;
      const APosition: TTextPosition): TArray<TJSONObject>; static;
    /// <summary>Standardwerte über AResolver (Baum der Datei festhalten, solange gebraucht).</summary>
    class function DefaultFunc(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName, AText: string): TOverloadDefaultFunc; static;
    /// <summary>Antwort auf atlas.server.createOverload; EJsonRpcError mit dem Grund, wenn es nicht geht. Der
    /// Aufrufer übernimmt das Objekt.</summary>
    class function Execute(ATree: TSyntaxTree; const AFileName, AText: string; const APosition: TTextPosition;
      const AKind: string; const ADefault: TOverloadDefaultFunc): TJSONObject; static;
  end;

implementation

uses
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Semantics.ConstantValues,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLspOverloadsText = (ThereIsNoHeaderOf, OverloadNotPossible, UnknownKind);

const
  cTexts: array[TLspOverloadsText] of TAtlasText = (
    (De: 'Hier steht kein Kopf einer Routine mit Rumpf in dieser Unit.';
     En: 'There is no header of a routine with a body in this unit here.'),
    (De: 'Überladung geht nicht: '; En: 'Overload not possible: '),
    (De: 'Unbekannte Art "%s"'; En: 'Unknown kind "%s"'));

{$SCOPEDENUMS OFF}

class function TLspOverloads.KindName(AKind: TOverloadKind): string;
begin
  if AKind = TOverloadKind.Forward then
  begin
    Result := cForwardName;
  end
  else
  begin
    Result := cCopyName;
  end;
end;

class function TLspOverloads.KindOf(const AName: string; out AKind: TOverloadKind): Boolean;
begin
  Result := True;
  if SameText(AName, cForwardName) then
  begin
    AKind := TOverloadKind.Forward;
  end
  else if SameText(AName, cCopyName) then
  begin
    AKind := TOverloadKind.Copy;
  end
  else
  begin
    AKind := TOverloadKind.Copy;
    Result := False;
  end;
end;

function NewAction(const AUri: string; const APosition: TTextPosition; const ATarget: TOverloadTarget;
  AKind: TOverloadKind): TJSONObject;
var
  mCommand: TJSONObject;
  mArguments: TJSONArray;
  mTitle, mReason: string;
begin
  mTitle := ATarget.Title(AKind);
  mReason := ATarget.Reason(AKind);
  Result := TJSONObject.Create;
  Result.AddPair('title', mTitle);
  Result.AddPair('kind', TLspOverloads.cActionKind);
  if mReason <> '' then
  begin
    Result.AddPair('disabled', TJSONObject.Create(TJSONPair.Create('reason', mReason)));
    Exit;
  end;
  mArguments := TJSONArray.Create;
  mArguments.Add(AUri);
  mArguments.AddElement(TLspPositions.PositionToJson(APosition));
  mArguments.Add(TLspOverloads.KindName(AKind));
  mCommand := TJSONObject.Create;
  mCommand.AddPair('title', mTitle);
  mCommand.AddPair('command', TLspOverloads.cClientCommand);
  mCommand.AddPair('arguments', mArguments);
  Result.AddPair('command', mCommand);
end;

class function TLspOverloads.Actions(ATree: TSyntaxTree; const AText, AUri: string;
  const APosition: TTextPosition): TArray<TJSONObject>;
var
  mTarget: TOverloadTarget;
begin
  Result := nil;
  if not TOverloads.Target(AText, ATree, APosition, mTarget) then
  begin
    Exit;
  end;
  Result := [NewAction(AUri, APosition, mTarget, TOverloadKind.Forward),
    NewAction(AUri, APosition, mTarget, TOverloadKind.Copy)];
end;

/// <summary>Erstes Element der Aufzählung ASymbol; '' ohne.</summary>
function FirstMember(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const ASymbol: TResolvedSymbol): string;
var
  mValues: TConstantValues;
  mNames: TArray<string>;
begin
  Result := '';
  mValues := TConstantValues.Create(ATree, AFileName, AIndex, AResolver);
  try
    if mValues.EnumMembers(ASymbol, mNames) and (Length(mNames) > 0) then
    begin
      Result := mNames[0];
    end;
  finally
    mValues.Free;
  end;
end;

class function TLspOverloads.DefaultFunc(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName, AText: string): TOverloadDefaultFunc;
var
  mLines: TLineTable;
begin
  mLines := TLineTable.Build(AText);
  Result :=
    function(const ATypeName: string; ATypeOffset: Integer): string
    var
      Resolved: TResolvedSymbol;
    begin
      Result := '';
      if ATypeOffset < 0 then
      begin
        Exit;
      end;
      Resolved := AResolver.ResolveType(ATree, AFileName, mLines.PositionAt(ATypeOffset));
      if not Resolved.Found then
      begin
        Exit;
      end;
      case Resolved.SymbolKind of
        TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType:
          Result := 'nil';
        TIndexSymbolKind.EnumType:
          Result := FirstMember(AResolver, AIndex, ATree, AFileName, Resolved);
      else
        // Übrige Typarten ohne Vorgabewert.
      end;
    end;
end;

function Fail(const AMessage: string): EJsonRpcError;
begin
  Result := EJsonRpcError.Create(TLspErrorCode.cRequestFailed, AMessage);
end;

function AnswerJson(const AUri: string; const AResult: TOverloadResult): TJSONObject;
var
  mDocument, mItem, mEdit, mChange: TJSONObject;
  mItems, mChanges, mPlaceholders, mWarnings: TJSONArray;
  mTextEdit: TTextEdit;
  mPlaceholder: TOverloadPlaceholder;
  mWarning: string;
begin
  mDocument := TJSONObject.Create;
  mDocument.AddPair('uri', AUri);
  mDocument.AddPair('version', TJSONNull.Create);
  mItems := TJSONArray.Create;
  for mTextEdit in AResult.Edits do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('range', TLspPositions.RangeToJson(mTextEdit.Range));
    mItem.AddPair('newText', mTextEdit.NewText);
    mItems.AddElement(mItem);
  end;
  mChange := TJSONObject.Create;
  mChange.AddPair('textDocument', mDocument);
  mChange.AddPair('edits', mItems);
  mChanges := TJSONArray.Create;
  mChanges.AddElement(mChange);
  mEdit := TJSONObject.Create;
  mEdit.AddPair('documentChanges', mChanges);
  mPlaceholders := TJSONArray.Create;
  for mPlaceholder in AResult.Placeholders do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('number', TJSONNumber.Create(mPlaceholder.Number));
    mItem.AddPair('range', TLspPositions.RangeToJson(mPlaceholder.Range));
    mPlaceholders.AddElement(mItem);
  end;
  mWarnings := TJSONArray.Create;
  for mWarning in AResult.Warnings do
  begin
    mWarnings.Add(mWarning);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('edit', mEdit);
  Result.AddPair('placeholders', mPlaceholders);
  Result.AddPair('warnings', mWarnings);
end;

class function TLspOverloads.Execute(ATree: TSyntaxTree; const AFileName, AText: string;
  const APosition: TTextPosition; const AKind: string; const ADefault: TOverloadDefaultFunc): TJSONObject;
var
  mKind: TOverloadKind;
  mTarget: TOverloadTarget;
  mOutcome: TOverloadResult;
  mReason: string;
begin
  if not KindOf(AKind, mKind) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TLspOverloadsText.UnknownKind].Fmt([AKind]));
  end;
  if not TOverloads.Target(AText, ATree, APosition, mTarget) then
  begin
    raise Fail(cTexts[TLspOverloadsText.ThereIsNoHeaderOf].Text);
  end;
  if not TOverloads.Build(AText, ATree, mTarget, TOverloadRequest.Create(mKind, ADefault), mOutcome, mReason) then
  begin
    raise Fail(cTexts[TLspOverloadsText.OverloadNotPossible].Text + mReason);
  end;
  Result := AnswerJson(TDocumentUris.FromPath(AFileName), mOutcome);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Overloads', cTexts);

end.
