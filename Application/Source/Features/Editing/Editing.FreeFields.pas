unit Editing.FreeFields;

// Code-Aktionen „Im Destruktor freigeben“ (#666): auf dem Feld, das die Klasse erzeugt und nicht
// freigibt, und auf der Kopfzeile der Klasse für alle solchen Felder. Welche Felder das sind, sagt
// TOwnedFields (Semantics), wohin die Freigabe kommt, TPascalDestructors.

interface

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Destructors,
  Atlas.Common.CodeActions.Contract;

type
  TFreeFields = class
  public
    class function FieldTitle: string; static;
    class function ClassTitle: string; static;
    /// <summary>Auf der Deklaration eines nicht freigegebenen Felds „Im Destruktor freigeben“ (nur mit
    /// AWithFieldAction) und, ab zwei Feldern, die Aktion für die ganze Klasse; auf der Kopfzeile der Klasse
    /// „Alle eigenen Objekte freigeben (n)“.</summary>
    class function Actions(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex; ALine: Integer;
      AStyle: TFreeFieldsStyle; AWithFieldAction: Boolean): TArray<TCodeAction>; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Semantics.OwnedFields,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TFreeFieldsText = (FreeInTheDestructor, FreeAllOwnedObjects);

const
  cTexts: array[TFreeFieldsText] of TAtlasText = (
    (De: 'Im Destruktor freigeben'; En: 'Free in the destructor'),
    (De: 'Alle eigenen Objekte freigeben (%d)'; En: 'Free all owned objects (%d)'));

{$SCOPEDENUMS OFF}

{ TFreeFields }

class function TFreeFields.FieldTitle: string;
begin
  Result := cTexts[TFreeFieldsText.FreeInTheDestructor].Text;
end;

class function TFreeFields.ClassTitle: string;
begin
  Result := cTexts[TFreeFieldsText.FreeAllOwnedObjects].Text;
end;

/// <summary>Treffer auf Zeile ALine: ein nicht freigegebenes Feld dort oder die Kopfzeile seiner Klasse.</summary>
function FindHit(const AAll: TArray<TOwnedField>; ALine: Integer; out AHit: TOwnedField;
  out AOnField, AOnClass: Boolean): Boolean;
var
  mField: TOwnedField;
begin
  AHit := Default(TOwnedField);
  AOnField := False;
  AOnClass := False;
  for mField in AAll do
  begin
    if (mField.State = TOwnedFieldState.NotFreed) and (mField.Range.StartPos.Line = ALine) then
    begin
      AHit := mField;
      AOnField := True;
      Break;
    end;
    if (mField.State = TOwnedFieldState.NotFreed) and (mField.ClassLine = ALine) then
    begin
      AHit := mField;
      AOnClass := True;
    end;
  end;
  Result := AOnField or AOnClass;
end;

/// <summary>Nicht freigegebene Felder der Klasse von AHit.</summary>
function FieldsOfClass(const AAll: TArray<TOwnedField>; const AHit: TOwnedField): TArray<TOwnedField>;
var
  mField: TOwnedField;
begin
  Result := nil;
  for mField in AAll do
  begin
    if (mField.State = TOwnedFieldState.NotFreed) and (mField.ClassLine = AHit.ClassLine) and
      SameText(mField.ClassName, AHit.ClassName) then
    begin
      Result := Result + [mField];
    end;
  end;
end;

function FixAction(const ATitle: string; const AEdits: TArray<TTextEdit>; APreferred: Boolean): TCodeAction;
begin
  Result := Default(TCodeAction);
  Result.Title := ATitle;
  Result.Kind := cQuickFixKind;
  Result.Edits := AEdits;
  Result.IsPreferred := APreferred;
end;

class function TFreeFields.Actions(ATree: TSyntaxTree; const AText: string; const AIndex: ISymbolIndex;
  ALine: Integer; AStyle: TFreeFieldsStyle; AWithFieldAction: Boolean): TArray<TCodeAction>;
var
  mAll, mOfClass: TArray<TOwnedField>;
  mHit: TOwnedField;
  mOnField, mOnClass: Boolean;
  mEdits: TArray<TTextEdit>;
begin
  Result := nil;
  mAll := TOwnedFields.Analyze(ATree, AText, AIndex);
  if not FindHit(mAll, ALine, mHit, mOnField, mOnClass) then
  begin
    Exit;
  end;
  mOfClass := FieldsOfClass(mAll, mHit);
  if mOnField and AWithFieldAction and
    TOwnedFields.FreeEdits(ATree, AText, TArray<TOwnedField>.Create(mHit), AStyle, mEdits) then
  begin
    Result := Result + [FixAction(FieldTitle, mEdits, True)];
  end;
  if (mOnClass or (Length(mOfClass) >= 2)) and TOwnedFields.FreeEdits(ATree, AText, mOfClass, AStyle, mEdits) then
  begin
    Result := Result + [FixAction(Format(ClassTitle, [Length(mOfClass)]), mEdits, False)];
  end;
end;

initialization
  TAtlasTextTables.Add('Editing.FreeFields', cTexts);

end.
