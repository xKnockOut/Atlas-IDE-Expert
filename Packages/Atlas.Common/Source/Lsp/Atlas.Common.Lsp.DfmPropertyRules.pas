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
  Atlas.Common.Lsp.Positions;

function Before(const X, Y: TTextPosition): Boolean;
begin
  Result := (X.Line < Y.Line) or ((X.Line = Y.Line) and (X.Character <= Y.Character));
end;

function Overlaps(const A, B: TTextRange): Boolean;
begin
  // Bereiche, die sich nur berühren (auch zwei Einfügungen an einer Stelle), überlappen nicht.
  Result := not (Before(A.EndPos, B.StartPos) or Before(B.EndPos, A.StartPos));
end;

{ TLspDfmPropertyRules }

class function TLspDfmPropertyRules.UnitOf(const AFileName: string): string;
begin
  if SameText(ExtractFileExt(AFileName), '.dfm') or SameText(ExtractFileExt(AFileName), '.fmx') then
    Result := ChangeFileExt(AFileName, '.pas')
  else
    Result := AFileName;
end;

class function TLspDfmPropertyRules.BuildEdit(const AUnits: TArray<string>; const ACheck: TDfmRulesCheckFunc;
  out AFiles, AEdits: Integer): TJSONObject;
var
  Order: TList<string>;
  Edits: TDictionary<string, TArray<TRuleEdit>>;
  Seen: TDictionary<string, Boolean>;
  UnitFile, FileName: string;
  Findings: TArray<TRuleFinding>;
  Finding: TRuleFinding;
  Fix: TRuleFix;
  Edit, Taken: TRuleEdit;
  Existing: TArray<TRuleEdit>;
  Fits: Boolean;
  Changes, Items: TJSONArray;
  Document, Item, Entry, Annotations, Annotation: TJSONObject;
begin
  AFiles := 0;
  AEdits := 0;
  Order := TList<string>.Create;
  Edits := TDictionary<string, TArray<TRuleEdit>>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  try
    for UnitFile in AUnits do
    begin
      if Seen.ContainsKey(UpperCase(UnitFile)) then
        Continue;
      Seen.Add(UpperCase(UnitFile), True);
      if not ACheck(UnitFile, Findings) then
        Continue;
      for Finding in Findings do
      begin
        if not SameText(Finding.RuleId, RuleId) then
          Continue;
        for Fix in Finding.Fixes do
        begin
          // Nur Korrekturen in der Formulardatei; die erste je Treffer.
          if Fix.FileName = '' then
            Continue;
          if not Edits.TryGetValue(UpperCase(Fix.FileName), Existing) then
          begin
            Existing := nil;
            Order.Add(Fix.FileName);
          end;
          Fits := True;
          for Edit in Fix.Edits do
            for Taken in Existing do
              if Overlaps(Edit.Range, Taken.Range) then
                Fits := False;
          if Fits then
            Existing := Existing + Fix.Edits;
          Edits.AddOrSetValue(UpperCase(Fix.FileName), Existing);
          Break;
        end;
      end;
    end;
    Changes := TJSONArray.Create;
    for FileName in Order do
    begin
      Existing := Edits[UpperCase(FileName)];
      if Length(Existing) = 0 then
        Continue;
      Document := TJSONObject.Create;
      Document.AddPair('uri', TDocumentUris.FromPath(FileName));
      Document.AddPair('version', TJSONNull.Create);
      Items := TJSONArray.Create;
      for Edit in Existing do
      begin
        Item := TJSONObject.Create;
        Item.AddPair('range', TLspPositions.RangeToJson(Edit.Range));
        Item.AddPair('newText', Edit.NewText);
        Item.AddPair('annotationId', AnnotationId);
        Items.AddElement(Item);
      end;
      Entry := TJSONObject.Create;
      Entry.AddPair('textDocument', Document);
      Entry.AddPair('edits', Items);
      Changes.AddElement(Entry);
      Inc(AFiles);
      Inc(AEdits, Length(Existing));
    end;
  finally
    Seen.Free;
    Edits.Free;
    Order.Free;
  end;
  Annotation := TJSONObject.Create;
  Annotation.AddPair('label', 'Eigenschaftsregeln anwenden');
  Annotation.AddPair('needsConfirmation', TJSONBool.Create(True));
  Annotation.AddPair('description', Format('%d Änderungen in %d Formulardateien', [AEdits, AFiles]));
  Annotations := TJSONObject.Create;
  Annotations.AddPair(AnnotationId, Annotation);
  Result := TJSONObject.Create;
  Result.AddPair('documentChanges', Changes);
  Result.AddPair('changeAnnotations', Annotations);
end;

end.
