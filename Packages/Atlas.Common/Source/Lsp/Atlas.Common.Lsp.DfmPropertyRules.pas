unit Atlas.Common.Lsp.DfmPropertyRules;

// Befehl „Eigenschaftsregeln anwenden“ (#309) für das aktuelle Formular, das
// Projekt oder die Projektgruppe: Je Unit mit Formulardatei prüft der Aufrufer
// nur die Regel dfm-property; ihre Korrekturen in den Formulardateien kommen
// als ein WorkspaceEdit mit Änderungsanmerkung (needsConfirmation) zurück.
// Der Client zeigt die Vorschau und übernimmt erst nach Bestätigung. Sonst
// ändert der Befehl nichts, auch nicht die Units. Überlappende Korrekturen
// derselben Stelle (zwei Regeln auf eine gespeicherte Property) entfallen bis
// auf die erste; der nächste Lauf holt den Rest.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Rules.Contract;

type
  /// <summary>Prüft die Unit AFileName nur mit der Regel dfm-property; False ohne Formular oder Regeln.</summary>
  TDfmRulesCheckFunc = reference to function(const AFileName: string; out AFindings: TArray<TRuleFinding>): Boolean;

  TLspDfmPropertyRules = class
  public const
    /// <summary>Argumente: URI einer Unit oder Formulardatei, Bereich form, project oder group.</summary>
    Command = 'atlas.server.applyDfmPropertyRules';
    RuleId = 'dfm-property';
    AnnotationId = 'dfmPropertyRules';
    ScopeForm = 'form';
    ScopeProject = 'project';
    ScopeGroup = 'group';
  public
    /// <summary>Unit zu einer Formulardatei (.dfm/.fmx → .pas); andere Dateien bleiben.</summary>
    class function UnitOf(const AFileName: string): string; static;
    /// <summary>WorkspaceEdit mit documentChanges über alle betroffenen Formulardateien. AFiles und AEdits
    /// zählen Dateien und Änderungen. Der Aufrufer übernimmt das Objekt.</summary>
    class function BuildEdit(const AUnits: TArray<string>; const ACheck: TDfmRulesCheckFunc;
      out AFiles, AEdits: Integer): TJSONObject; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TDfmPropertyRulesText = (ChangesInFormFiles, ApplyPropertyRules);

const
  cTexts: array[TDfmPropertyRulesText] of TAtlasText = (
    (De: '%d Änderungen in %d Formulardateien'; En: '%d changes in %d form files'),
    (De: 'Eigenschaftsregeln anwenden'; En: 'Apply property rules'));

{$SCOPEDENUMS OFF}

function Before(const X, Y: TTextPosition): Boolean;
begin
  Result := (X.Line < Y.Line) or ((X.Line = Y.Line) and (X.Character <= Y.Character));
end;

function Overlaps(const A, B: TTextRange): Boolean;
begin
  // Bereiche, die sich nur berühren (auch zwei Einfügungen an einer Stelle), überlappen nicht.
  Result := not (Before(A.EndPos, B.StartPos) or Before(B.EndPos, A.StartPos));
end;

/// <summary>True, wenn kein Edit aus AEdits einen aus ATaken überlappt.</summary>
function FitsBeside(const AEdits, ATaken: TArray<TRuleEdit>): Boolean;
var
  mEdit, mTaken: TRuleEdit;
begin
  for mEdit in AEdits do
  begin
    for mTaken in ATaken do
    begin
      if Overlaps(mEdit.Range, mTaken.Range) then
      begin
        Exit(False);
      end;
    end;
  end;
  Result := True;
end;

/// <summary>Ein Eintrag von documentChanges für AFileName mit den Änderungen AEdits.</summary>
function DocumentChange(const AFileName: string; const AEdits: TArray<TRuleEdit>;
  const AAnnotationId: string): TJSONObject;
var
  mEdit: TRuleEdit;
  mDocument, mItem: TJSONObject;
  mItems: TJSONArray;
begin
  mDocument := TJSONObject.Create;
  mDocument.AddPair('uri', TDocumentUris.FromPath(AFileName));
  mDocument.AddPair('version', TJSONNull.Create);
  mItems := TJSONArray.Create;
  for mEdit in AEdits do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('range', TLspPositions.RangeToJson(mEdit.Range));
    mItem.AddPair('newText', mEdit.NewText);
    mItem.AddPair('annotationId', AAnnotationId);
    mItems.AddElement(mItem);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', mDocument);
  Result.AddPair('edits', mItems);
end;

/// <summary>changeAnnotations mit der Bestätigung für AEdits Änderungen in AFiles Dateien.</summary>
function ChangeAnnotations(const AAnnotationId: string; AFiles, AEdits: Integer): TJSONObject;
var
  mAnnotation: TJSONObject;
begin
  mAnnotation := TJSONObject.Create;
  mAnnotation.AddPair('label', cTexts[TDfmPropertyRulesText.ApplyPropertyRules].Text);
  mAnnotation.AddPair('needsConfirmation', TJSONBool.Create(True));
  mAnnotation.AddPair('description', cTexts[TDfmPropertyRulesText.ChangesInFormFiles].Fmt([AEdits, AFiles]));
  Result := TJSONObject.Create;
  Result.AddPair(AAnnotationId, mAnnotation);
end;

type
  /// <summary>Sammelt die Korrekturen je Formulardatei in der Reihenfolge ihres ersten Auftretens.</summary>
  TDfmEditCollector = class
  private
    FOrder: TList<string>;
    FEdits: TDictionary<string, TArray<TRuleEdit>>;
    FSeen: TDictionary<string, Boolean>;
    procedure AddFix(const AFix: TRuleFix);
    procedure AddFinding(const AFinding: TRuleFinding);
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddUnit(const AUnitFile: string; const ACheck: TDfmRulesCheckFunc);
    function Changes(out AFiles, AEdits: Integer): TJSONArray;
  end;

constructor TDfmEditCollector.Create;
begin
  inherited Create;
  FOrder := TList<string>.Create;
  FEdits := TDictionary<string, TArray<TRuleEdit>>.Create;
  FSeen := TDictionary<string, Boolean>.Create;
end;

destructor TDfmEditCollector.Destroy;
begin
  FSeen.Free;
  FEdits.Free;
  FOrder.Free;
  inherited;
end;

procedure TDfmEditCollector.AddFix(const AFix: TRuleFix);
var
  mExisting: TArray<TRuleEdit>;
begin
  if not FEdits.TryGetValue(UpperCase(AFix.FileName), mExisting) then
  begin
    mExisting := nil;
    FOrder.Add(AFix.FileName);
  end;
  if FitsBeside(AFix.Edits, mExisting) then
  begin
    mExisting := mExisting + AFix.Edits;
  end;
  FEdits.AddOrSetValue(UpperCase(AFix.FileName), mExisting);
end;

procedure TDfmEditCollector.AddFinding(const AFinding: TRuleFinding);
var
  mFix: TRuleFix;
begin
  // Nur Korrekturen in der Formulardatei; die erste je Treffer.
  for mFix in AFinding.Fixes do
  begin
    if mFix.FileName <> '' then
    begin
      AddFix(mFix);
      Exit;
    end;
  end;
end;

procedure TDfmEditCollector.AddUnit(const AUnitFile: string; const ACheck: TDfmRulesCheckFunc);
var
  mFindings: TArray<TRuleFinding>;
  mFinding: TRuleFinding;
begin
  if FSeen.ContainsKey(UpperCase(AUnitFile)) then
  begin
    Exit;
  end;
  FSeen.Add(UpperCase(AUnitFile), True);
  if not ACheck(AUnitFile, mFindings) then
  begin
    Exit;
  end;
  for mFinding in mFindings do
  begin
    if SameText(mFinding.RuleId, TLspDfmPropertyRules.RuleId) then
    begin
      AddFinding(mFinding);
    end;
  end;
end;

function TDfmEditCollector.Changes(out AFiles, AEdits: Integer): TJSONArray;
var
  mFileName: string;
  mExisting: TArray<TRuleEdit>;
begin
  AFiles := 0;
  AEdits := 0;
  Result := TJSONArray.Create;
  for mFileName in FOrder do
  begin
    mExisting := FEdits[UpperCase(mFileName)];
    if Length(mExisting) = 0 then
    begin
      Continue;
    end;
    Result.AddElement(DocumentChange(mFileName, mExisting, TLspDfmPropertyRules.AnnotationId));
    Inc(AFiles);
    Inc(AEdits, Length(mExisting));
  end;
end;

{ TLspDfmPropertyRules }

class function TLspDfmPropertyRules.UnitOf(const AFileName: string): string;
begin
  if SameText(ExtractFileExt(AFileName), '.dfm') or SameText(ExtractFileExt(AFileName), '.fmx') then
  begin
    Result := ChangeFileExt(AFileName, '.pas');
  end
  else
  begin
    Result := AFileName;
  end;
end;

class function TLspDfmPropertyRules.BuildEdit(const AUnits: TArray<string>; const ACheck: TDfmRulesCheckFunc;
  out AFiles, AEdits: Integer): TJSONObject;
var
  mCollector: TDfmEditCollector;
  mUnitFile: string;
  mChanges: TJSONArray;
begin
  mCollector := TDfmEditCollector.Create;
  try
    for mUnitFile in AUnits do
    begin
      mCollector.AddUnit(mUnitFile, ACheck);
    end;
    mChanges := mCollector.Changes(AFiles, AEdits);
  finally
    mCollector.Free;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('documentChanges', mChanges);
  Result.AddPair('changeAnnotations', ChangeAnnotations(AnnotationId, AFiles, AEdits));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.DfmPropertyRules', cTexts);

end.
