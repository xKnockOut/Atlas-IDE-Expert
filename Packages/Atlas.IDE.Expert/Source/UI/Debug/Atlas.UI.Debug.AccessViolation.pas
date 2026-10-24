unit Atlas.UI.Debug.AccessViolation;

// Zugriffsverletzung erklären (#865), Texte: aus dem Ergebnis von TAtlasAvAnalysis die Erklärung für die
// Exception-Leiste (Ergebniszeile, Feld bzw. Füllmuster, geprüfte Glieder mit ✓/✗), den Text für „Erklärung
// kopieren“ und die Zeilen für die Meldungen, wenn keine Leiste steht (debug.exceptionBanner aus).

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.AccessChains,
  Atlas.Core.Debug.AccessViolation,
  Atlas.Core.Debug.ExceptionBanner;

type
  TAtlasAvTexts = class
  public
    /// <summary>Während Atlas prüft: nur die Ergebniszeile.</summary>
    class function Busy: TAtlasDebugBannerExplanation; static;
    /// <summary>Keine Prüfung möglich (Server antwortet nicht, keine Kette): „Ursache nicht eindeutig“ und der
    /// Grund.</summary>
    class function Failed(const AReason, AHeader: string): TAtlasDebugBannerExplanation; static;
    /// <summary>Ergebnis der fertigen Analyse. ACanWhere: Knopf „Wo wird X zugewiesen?“ (navigation.dataFlow),
    /// ACanEvaluate: Knopf „Ausdruck auswerten“ (debug.evaluateWindow). AHeader: Meldung und Ort für den
    /// kopierten Text.</summary>
    class function FromAnalysis(AAnalysis: TAtlasAvAnalysis; ACanWhere, ACanEvaluate: Boolean;
      const AHeader: string): TAtlasDebugBannerExplanation; static;
    /// <summary>Eine Zeile der geprüften Glieder.</summary>
    class function CheckLine(AAnalysis: TAtlasAvAnalysis; AIndex: Integer): TAtlasDebugBannerLine; static;
    /// <summary>Zeilen für die Meldungen: erste mit Ort und Ergebnis, dann die Glieder eingerückt.</summary>
    class function MessageLines(const AExplanation: TAtlasDebugBannerExplanation;
      const APlace: string): TArray<string>; static;
    /// <summary>Versatz kurz: $1C, $08.</summary>
    class function OffsetText(AOffset: Integer): string; static;
  end;

implementation

uses
  Atlas.UI.Strings;

function HeadlineOf(const AVerdict: TAtlasAvVerdict; const AMessage: TAtlasAvMessage; APointerSize: Integer;
  out ADetail: string): string;
begin
  ADetail := '';
  case AVerdict.Kind of
    TAtlasAvVerdictKind.NilLink:
      begin
        Result := TAtlasStrings.Fmt(TAtlasTextId.DebugAvNil, [AVerdict.Culprit.Expression]);
        if AVerdict.VmtAccess then
          ADetail := TAtlasStrings.Text(TAtlasTextId.DebugAvVmt)
        else if (AVerdict.Field <> '') and AVerdict.FieldExact then
          ADetail := TAtlasStrings.Fmt(TAtlasTextId.DebugAvField, [AVerdict.Field,
            TAtlasAvTexts.OffsetText(AVerdict.FieldOffset)])
        else if AVerdict.Field <> '' then
          ADetail := TAtlasStrings.Fmt(TAtlasTextId.DebugAvFieldEstimated, [AVerdict.Field,
            TAtlasAvTexts.OffsetText(AVerdict.FieldOffset)])
        else if AMessage.AddressKnown and (AMessage.Address > 0) and
          (AMessage.Address < TAtlasAvAnalysis.NearNil) then
          ADetail := TAtlasStrings.Fmt(TAtlasTextId.DebugAvOffset,
            [TAtlasAvTexts.OffsetText(Integer(AMessage.Address))]);
      end;
    TAtlasAvVerdictKind.Freed:
      begin
        Result := TAtlasStrings.Fmt(TAtlasTextId.DebugAvFreed, [AVerdict.Culprit.Expression]);
        if TAtlasAvAnalysis.IsFreedPattern(AVerdict.Value, APointerSize) then
          ADetail := TAtlasStrings.Fmt(TAtlasTextId.DebugAvFreedPattern, [TAtlasAvAnalysis.HexText(AVerdict.Value)])
        else
          ADetail := TAtlasStrings.Text(TAtlasTextId.DebugAvFreedHeader);
      end;
    TAtlasAvVerdictKind.FreedMemory:
      begin
        Result := TAtlasStrings.Text(TAtlasTextId.DebugAvFreedMemory);
        ADetail := TAtlasStrings.Fmt(TAtlasTextId.DebugAvFreedMemoryDetail, [TAtlasAvAnalysis.HexText(AVerdict.Value)]);
      end;
    TAtlasAvVerdictKind.Invalid:
      Result := TAtlasStrings.Fmt(TAtlasTextId.DebugAvInvalid, [AVerdict.Culprit.Expression,
        TAtlasAvAnalysis.HexText(AVerdict.Value)]);
    TAtlasAvVerdictKind.OutOfRange:
      Result := TAtlasStrings.Fmt(TAtlasTextId.DebugAvOutOfRange, [AVerdict.Culprit.IndexText, AVerdict.Index,
        AVerdict.Culprit.Expression, AVerdict.Length]);
  else
    begin
      Result := TAtlasStrings.Text(TAtlasTextId.DebugAvAmbiguous);
      if AVerdict.Causes > 1 then
        ADetail := TAtlasStrings.Fmt(TAtlasTextId.DebugAvAmbiguousSeveral, [AVerdict.Causes])
      else
        ADetail := TAtlasStrings.Text(TAtlasTextId.DebugAvAmbiguousNone);
    end;
  end;
end;

function CopyTextOf(const AExplanation: TAtlasDebugBannerExplanation; const AHeader: string): string;
var
  Parts: TArray<string>;
  Line: TAtlasDebugBannerLine;
begin
  Parts := TArray<string>.Create(TAtlasStrings.Text(TAtlasTextId.DebugAvCopyHeader), AExplanation.Headline);
  if AExplanation.Detail <> '' then
    Parts := Parts + [AExplanation.Detail];
  if AHeader <> '' then
    Parts := Parts + [AHeader];
  if AExplanation.Lines <> nil then
  begin
    Parts := Parts + [TAtlasStrings.Text(TAtlasTextId.DebugAvCopyChecked)];
    for Line in AExplanation.Lines do
      Parts := Parts + ['  ' + TAtlasDebugBannerLine.MarkText(Line.Mark) + ' ' + Line.Text];
  end;
  Result := string.Join(sLineBreak, Parts);
end;

{ TAtlasAvTexts }

class function TAtlasAvTexts.OffsetText(AOffset: Integer): string;
begin
  Result := '$' + IntToHex(AOffset, 2);
end;

class function TAtlasAvTexts.Busy: TAtlasDebugBannerExplanation;
begin
  Result := Default(TAtlasDebugBannerExplanation);
  Result.Active := True;
  Result.Busy := True;
  Result.Headline := TAtlasStrings.Text(TAtlasTextId.DebugAvAnalysing);
end;

class function TAtlasAvTexts.Failed(const AReason, AHeader: string): TAtlasDebugBannerExplanation;
begin
  Result := Default(TAtlasDebugBannerExplanation);
  Result.Active := True;
  Result.HeadlineMark := TAtlasDebugBannerMark.Neutral;
  Result.Headline := TAtlasStrings.Text(TAtlasTextId.DebugAvAmbiguous);
  Result.Detail := AReason;
  Result.CopyText := CopyTextOf(Result, AHeader);
end;

class function TAtlasAvTexts.CheckLine(AAnalysis: TAtlasAvAnalysis; AIndex: Integer): TAtlasDebugBannerLine;
var
  Check: TAtlasAvCheck;
  Value: string;
begin
  Check := AAnalysis.Checks[AIndex];
  Value := Check.Value;
  if Check.State = TAtlasAvCheckState.NilValue then
    Value := 'nil';
  case Check.State of
    TAtlasAvCheckState.Ok:
      Result := TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Ok, Check.Expression + ' = ' + Value);
    TAtlasAvCheckState.NilValue:
      Result := TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Bad, Check.Expression + ' = ' + Value);
    TAtlasAvCheckState.Freed:
      Result := TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Bad, Check.Expression + ' = ' + Value + ' (' +
        TAtlasStrings.Text(TAtlasTextId.DebugAvStateFreed) + ')');
    TAtlasAvCheckState.Invalid:
      Result := TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Bad, Check.Expression + ' = ' + Value + ' (' +
        TAtlasStrings.Text(TAtlasTextId.DebugAvStateInvalid) + ')');
    TAtlasAvCheckState.OutOfRange:
      Result := TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Bad, Check.Expression + ' = ' + Value + ' (' +
        TAtlasStrings.Text(TAtlasTextId.DebugAvStateOutOfRange) + ')');
    TAtlasAvCheckState.NotReached:
      Result := TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Neutral, Check.Expression + ': ' +
        TAtlasStrings.Text(TAtlasTextId.DebugAvStateNotReached));
    TAtlasAvCheckState.Failed:
      Result := TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Neutral, Check.Expression + ': ' +
        TAtlasStrings.Text(TAtlasTextId.DebugAvStateFailed));
  else
    // Nicht ausgewertet: wegen eines Aufrufs ohne allowCalls oder weil die Prüfung abbrach.
    if AAnalysis.LinkOf(AIndex).Call and not AAnalysis.AllowCalls then
      Result := TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Neutral, Check.Expression + ': ' +
        TAtlasStrings.Text(TAtlasTextId.DebugAvStateCall))
    else
      Result := TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Neutral, Check.Expression + ': ' +
        TAtlasStrings.Text(TAtlasTextId.DebugAvStateNotEvaluated));
  end;
end;

class function TAtlasAvTexts.FromAnalysis(AAnalysis: TAtlasAvAnalysis; ACanWhere, ACanEvaluate: Boolean;
  const AHeader: string): TAtlasDebugBannerExplanation;
var
  Verdict: TAtlasAvVerdict;
  Index: Integer;
  Detail: string;
begin
  Result := Default(TAtlasDebugBannerExplanation);
  Result.Active := True;
  Verdict := AAnalysis.Verdict;
  // Die Zeigergröße steckt in der Erkennung; für den Text genügt die größere Musterliste.
  Result.Headline := HeadlineOf(Verdict, AAnalysis.AccessMessage, 8, Detail);
  Result.Detail := Detail;
  if Verdict.HasCulprit or (Verdict.Kind = TAtlasAvVerdictKind.FreedMemory) then
    Result.HeadlineMark := TAtlasDebugBannerMark.Bad
  else
    Result.HeadlineMark := TAtlasDebugBannerMark.Neutral;
  if (AAnalysis.Chains.Statements > 1) and not Verdict.HasCulprit then
    if Result.Detail <> '' then
      Result.Detail := Result.Detail + ' ' + #$00B7 + ' ' +
        TAtlasStrings.Fmt(TAtlasTextId.DebugAvStatements, [AAnalysis.Chains.Statements])
    else
      Result.Detail := TAtlasStrings.Fmt(TAtlasTextId.DebugAvStatements, [AAnalysis.Chains.Statements]);
  for Index := 0 to High(AAnalysis.Checks) do
    Result.Lines := Result.Lines + [CheckLine(AAnalysis, Index)];
  // „Wo wird X zugewiesen?“ nur für ein benanntes Glied; Self wird nicht zugewiesen.
  if ACanWhere and Verdict.HasCulprit and (Verdict.Culprit.Name <> '') and
    not SameText(Verdict.Culprit.Name, 'Self') then
    Result.WhereName := Verdict.Culprit.Name;
  if ACanEvaluate then
    if Verdict.HasCulprit then
      Result.EvaluateExpression := Verdict.Culprit.Expression
    else if AAnalysis.Chains.Chains <> nil then
      Result.EvaluateExpression := AAnalysis.Chains.Chains[0].Text;
  Result.CopyText := CopyTextOf(Result, AHeader);
end;

class function TAtlasAvTexts.MessageLines(const AExplanation: TAtlasDebugBannerExplanation;
  const APlace: string): TArray<string>;
var
  Text: string;
  Line: TAtlasDebugBannerLine;
begin
  Text := AExplanation.Headline;
  if AExplanation.Detail <> '' then
    Text := Text + ' ' + #$00B7 + ' ' + AExplanation.Detail;
  Result := TArray<string>.Create(TAtlasStrings.Fmt(TAtlasTextId.DebugAvMessage, [APlace, Text]));
  for Line in AExplanation.Lines do
    Result := Result + ['  ' + TAtlasDebugBannerLine.MarkText(Line.Mark) + ' ' + Line.Text];
end;

end.
