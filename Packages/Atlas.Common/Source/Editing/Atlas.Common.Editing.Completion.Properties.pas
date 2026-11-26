unit Atlas.Common.Editing.Completion.Properties;

// Zugriffe in "property … read/write" (#31): passende Felder und Methoden, davor Feld und Zugriffsmethoden
// anlegen (#467). Editing meldet die Quelle an der Stelle TCompletionSlot.PropertyAccess an; in einer
// property-Zeile antwortet sie allein.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Completion.Contract,
  Atlas.Common.Completion.Request,
  Atlas.Common.Completion.Answer;

type
  TEditingPropertyCompletion = class
  public
    /// <summary>In "property Name: T read " bzw. "write " im Klassenrumpf (#31): Felder vom Typ T und Methoden
    /// mit passender Signatur (read: Funktion mit Ergebnis T und den Indexparametern; write: Prozedur mit den
    /// Indexparametern und einem Parameter vom Typ T), auch geerbte. Mit completion.createAccessors kommen
    /// davor „Feld F&lt;Name&gt; anlegen“ und „Get&lt;Name&gt;/Set&lt;Name&gt; anlegen“ (#467). False außerhalb
    /// dieses Kontexts.</summary>
    class function Items(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean; static;
    /// <summary>Quelle für TCompletionSlot.PropertyAccess: antwortet in einer property-Zeile mit Items allein.
    /// </summary>
    class function Source: TCompletionSource; static;
  end;

implementation

uses
  System.SysUtils,
  System.RegularExpressions,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.EnclosingTypes,
  Atlas.Common.Pascal.TypeConversions,
  Atlas.Common.Completion.FuzzyMatch,
  Atlas.Common.Completion.SymbolKinds,
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.ClassActions.Contract,
  Atlas.Common.Editing.AccessorCreation,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Texte der Einträge zum Anlegen in beiden Sprachen (#1458).</summary>
  TPropertyText = (CreateField, CreateMethod);

const
  cTexts: array[TPropertyText] of TAtlasText = (
    (De: 'Feld %s anlegen'; En: 'Create field %s'),
    (De: '%s anlegen'; En: 'Create %s'));
  cAccessorTitles: array[TAccessorKind] of TPropertyText = (TPropertyText.CreateField, TPropertyText.CreateMethod,
    TPropertyText.CreateMethod);

type
  /// <summary>Eine Property-Zeile "property Name[Index]: Typ read|write Anfang" im Klassenrumpf.</summary>
  TPropertySite = record
    Name: string;
    IndexParameters: string;
    PropertyType: string;
    IsWrite: Boolean;
    Prefix: string;
    TypeName: string;
  end;

/// <summary>Erkennt "  property Wert[I: Integer]: Double read |", auch mit "index 3" und schon gesetztem read
/// vor write, im Rumpf einer Klasse bzw. eines Records.</summary>
function PropertySiteAt(ARequest: TCompletionRequest; out ASite: TPropertySite): Boolean;
var
  mMatch: TMatch;
begin
  ASite := Default(TPropertySite);
  mMatch := TRegEx.Match(ARequest.LineBefore, '^\s*(?:class\s+)?property\s+(\w+)\s*(\[[^\]]*\])?\s*:\s*' +
    '([\w.<>, ]+?)\s+(?:index\s+\S+\s+)?(?:read\s+\w+\s+)?(read|write)\s+(\w*)$', [roIgnoreCase]);
  Result := mMatch.Success and EnclosingTypeName(ARequest.UnitIndex, ARequest.Position.Line, True, ASite.TypeName);
  if not Result then
  begin
    Exit;
  end;
  ASite.Name := mMatch.Groups[1].Value;
  ASite.IndexParameters := mMatch.Groups[2].Value.Trim(['[', ']']).Trim;
  ASite.PropertyType := mMatch.Groups[3].Value;
  ASite.IsWrite := SameText(mMatch.Groups[4].Value, 'write');
  ASite.Prefix := mMatch.Groups[5].Value;
end;

/// <summary>Zahl der Indexparameter: "I, J: Integer; const S: string" sind drei.</summary>
function IndexParameterCount(const AParameters: string): Integer;
var
  mParam: string;
begin
  Result := 0;
  for mParam in AParameters.Split([';']) do
  begin
    if Pos(':', mParam) > 0 then
    begin
      Inc(Result, Length(Copy(mParam, 1, Pos(':', mParam) - 1).Split([','])));
    end;
  end;
end;

/// <summary>Passt ACandidate als Zugriff: Feld vom Typ (ohne Index), Setter bzw. Getter mit den
/// Indexparametern.</summary>
function AccessorFits(const ACandidate: TResolvedSymbol; const ASite: TPropertySite; AIndexCount: Integer): Boolean;
begin
  if ACandidate.SymbolKind = TIndexSymbolKind.Field then
  begin
    Result := (AIndexCount = 0) and (PlainType(ACandidate.TypeName) = PlainType(ASite.PropertyType));
  end
  else if ASite.IsWrite then
  begin
    Result := (ACandidate.TypeName = '') and (ACandidate.MinArgs <= AIndexCount + 1) and
      (ACandidate.MaxArgs >= AIndexCount + 1) and (Length(ACandidate.ParamTypes) > AIndexCount);
    Result := Result and (PlainType(ACandidate.ParamTypes[AIndexCount]) = PlainType(ASite.PropertyType));
  end
  else
  begin
    Result := (ACandidate.TypeName <> '') and (PlainType(ACandidate.TypeName) = PlainType(ASite.PropertyType)) and
      (ACandidate.MinArgs <= AIndexCount) and (ACandidate.MaxArgs >= AIndexCount);
  end;
end;

/// <summary>Eintrag für ein passendes Feld bzw. eine passende Methode.</summary>
function AccessorCandidateItem(const ACandidate: TResolvedSymbol; const APrefix: string;
  AMatching: TCompletionMatching): TCompletionItem;
begin
  Result := Default(TCompletionItem);
  Result.Name := ACandidate.Name;
  Result.Kind := CompletionKindOf(ACandidate.SymbolKind);
  Result.Detail := ACandidate.TypeName;
  if ACandidate.TypeName = '' then
  begin
    Result.Detail := ACandidate.Container;
  end;
  Result.Container := ACandidate.Container;
  Result.Depth := ACandidate.Depth;
  Result.SourceFile := ACandidate.FileName;
  Result.SourcePosition := ACandidate.SelectionRange.StartPos;
  if (AMatching = TCompletionMatching.Fuzzy) and not ACandidate.Name.StartsWith(APrefix, True) then
  begin
    Result.FilterText := APrefix;
  end;
end;

/// <summary>Arten zum Anlegen: ein Feld nur ohne Indexparameter (read FWert[I] gibt es nicht), dazu Getter
/// bzw. Setter.</summary>
function AccessorKinds(const ASite: TPropertySite): TArray<TAccessorKind>;
begin
  Result := nil;
  if ASite.IndexParameters = '' then
  begin
    Result := [TAccessorKind.Field];
  end;
  if ASite.IsWrite then
  begin
    Result := Result + [TAccessorKind.Setter];
  end
  else
  begin
    Result := Result + [TAccessorKind.Getter];
  end;
end;

/// <summary>Plan für eine Art: Abschnitt der Methoden aus completion.accessorSection.</summary>
function AccessorPlan(ARequest: TCompletionRequest; const ASite: TPropertySite; AKind: TAccessorKind): TAccessorPlan;
begin
  Result := Default(TAccessorPlan);
  Result.Kind := AKind;
  Result.PropertyName := ASite.Name;
  Result.PropertyType := ASite.PropertyType.Trim;
  Result.IndexParameters := ASite.IndexParameters;
  Result.MethodSection := 'private';
  if ARequest.Settings.AccessorSection = TCompletionAccessorSection.Protected then
  begin
    Result.MethodSection := 'protected';
  end;
end;

/// <summary>Eintrag „Feld F&lt;Name&gt; anlegen“, „Get…“ bzw. „Set… anlegen“ zum Plan.</summary>
function AccessorItem(ARequest: TCompletionRequest; const ASite: TPropertySite; APlan: TAccessorPlan;
  const AEdits: TArray<TTextEdit>; AWithField: Boolean): TCompletionItem;
begin
  Result := Default(TCompletionItem);
  Result.Name := cTexts[cAccessorTitles[APlan.Kind]].Fmt([APlan.Name]);
  Result.Kind := cKindMethod;
  if APlan.Kind = TAccessorKind.Field then
  begin
    Result.Kind := cKindField;
  end;
  Result.Detail := TAccessorCreation.Declaration(APlan);
  Result.Fits := True;
  Result.Pinned := True;
  Result.Action := 'create';
  Result.HasTextEdit := True;
  // Der getippte Anfang wird zum Namen: "read Ca|" → "read FCaption".
  Result.TextEdit := TTextEdit.Create(TTextRange.Create(TTextPosition.Create(ARequest.Position.Line,
    ARequest.Position.Character - Length(ASite.Prefix)), ARequest.Position), APlan.Name);
  Result.AdditionalEdits := AEdits;
  if AWithField then
  begin
    APlan.Kind := TAccessorKind.Field;
    Result.Detail := Result.Detail + ' + ' + TAccessorCreation.Declaration(APlan);
  end;
end;

/// <summary>„Feld F&lt;Name&gt; anlegen“, „Get&lt;Name&gt; anlegen“ bzw. „Set&lt;Name&gt; anlegen“ (#467).</summary>
function AccessorItems(ARequest: TCompletionRequest; const ASite: TPropertySite): TArray<TCompletionItem>;
var
  mSource: TCommandSource;
  mClass: TIndexSymbol;
  mKind: TAccessorKind;
  mPlan: TAccessorPlan;
  mEdits: TArray<TTextEdit>;
  mWithField: Boolean;
begin
  Result := nil;
  mSource := CommandSourceFor(ARequest);
  try
    if not mSource.ClassAt(mClass) then
    begin
      Exit;
    end;
    for mKind in AccessorKinds(ASite) do
    begin
      mPlan := AccessorPlan(ARequest, ASite, mKind);
      if TAccessorCreation.Edits(mSource, ARequest.Index, mClass, mPlan, mEdits, mWithField) then
      begin
        Result := Result + [AccessorItem(ARequest, ASite, mPlan, mEdits, mWithField)];
      end;
    end;
  finally
    mSource.Free;
  end;
end;

{ TEditingPropertyCompletion }

class function TEditingPropertyCompletion.Items(ARequest: TCompletionRequest;
  out AItems: TCompletionItems): Boolean;
var
  mSite: TPropertySite;
  mIndexCount: Integer;
  mCandidate: TResolvedSymbol;
begin
  AItems := Default(TCompletionItems);
  Result := PropertySiteAt(ARequest, mSite);
  if not Result then
  begin
    Exit;
  end;
  // Feld und Zugriffsmethoden anlegen (#467): oben vor den passenden Mitgliedern.
  if ARequest.Settings.CreateAccessors then
  begin
    AItems.Items := AccessorItems(ARequest, mSite);
  end;
  mIndexCount := IndexParameterCount(mSite.IndexParameters);
  for mCandidate in ARequest.Resolver.Queries.AccessorCandidates(ARequest.UnitIndex, mSite.TypeName) do
  begin
    if AccessorFits(mCandidate, mSite, mIndexCount) and
      (MatchScore(mCandidate.Name, mSite.Prefix, ARequest.Matching) <> TFuzzyMatch.cNoMatch) then
    begin
      AItems.Items := AItems.Items + [AccessorCandidateItem(mCandidate, mSite.Prefix, ARequest.Matching)];
    end;
  end;
end;

class function TEditingPropertyCompletion.Source: TCompletionSource;
begin
  Result :=
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    begin
      Result := TCompletionOutcome.Next;
      if Items(ARequest, AAnswer.Exclusive) then
      begin
        Result := TCompletionOutcome.Answered;
      end;
    end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.Completion.Properties', cTexts);

end.
