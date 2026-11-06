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
  Atlas.UI.Debug.Strings;

/// <summary>Zusatz zu „X ist nil“: Zugriff auf die VMT, das Feld (genau bzw. geschätzt) oder der Versatz nahe nil;
/// '' ohne.</summary>
function NilDetail(const AVerdict: TAtlasAvVerdict; const AMessage: TAtlasAvMessage): string;
begin
  Result := '';
  if AVerdict.VmtAccess then
  begin
    Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvVmt);
  end
  else if (AVerdict.Field <> '') and AVerdict.FieldExact then
  begin
    Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugAvField, [AVerdict.Field,
      TAtlasAvTexts.OffsetText(AVerdict.FieldOffset)]);
  end
  else if AVerdict.Field <> '' then
  begin
    Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugAvFieldEstimated, [AVerdict.Field,
      TAtlasAvTexts.OffsetText(AVerdict.FieldOffset)]);
  end
  else if AMessage.AddressKnown and (AMessage.Address > 0) and
    (AMessage.Address < TAtlasAvAnalysis.NearNil) then
  begin
    Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugAvOffset,
      [TAtlasAvTexts.OffsetText(Integer(AMessage.Address))]);
  end;
end;

function HeadlineOf(const AVerdict: TAtlasAvVerdict; const AMessage: TAtlasAvMessage; APointerSize: Integer;
  out ADetail: string): string;
begin
  ADetail := '';
  case AVerdict.Kind of
    TAtlasAvVerdictKind.NilLink:
      begin
        Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugAvNil, [AVerdict.Culprit.Expression]);
        ADetail := NilDetail(AVerdict, AMessage);
      end;
    TAtlasAvVerdictKind.Freed:
      begin
        Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugAvFreed, [AVerdict.Culprit.Expression]);
        if TAtlasAvValues.IsFreedPattern(AVerdict.Value, APointerSize) then
        begin
          ADetail := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugAvFreedPattern,
            [TAtlasAvValues.HexText(AVerdict.Value)]);
        end
        else
        begin
          ADetail := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvFreedHeader);
        end;
      end;
    TAtlasAvVerdictKind.FreedMemory:
      begin
        Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvFreedMemory);
        ADetail := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugAvFreedMemoryDetail,
          [TAtlasAvValues.HexText(AVerdict.Value)]);
      end;
    TAtlasAvVerdictKind.Invalid:
      Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugAvInvalid, [AVerdict.Culprit.Expression,
        TAtlasAvValues.HexText(AVerdict.Value)]);
    TAtlasAvVerdictKind.OutOfRange:
      Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugAvOutOfRange, [AVerdict.Culprit.IndexText, AVerdict.Index,
        AVerdict.Culprit.Expression, AVerdict.Length]);
  else
    begin
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvAmbiguous);
      if AVerdict.Causes > 1 then
      begin
        ADetail := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugAvAmbiguousSeveral, [AVerdict.Causes]);
      end
      else
      begin
        ADetail := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvAmbiguousNone);
      end;
    end;
  end;
end;

function CopyTextOf(const AExplanation: TAtlasDebugBannerExplanation; const AHeader: string): string;
var
  Parts: TArray<string>;
  Line: TAtlasDebugBannerLine;
begin
  Parts := TArray<string>.Create(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvCopyHeader), AExplanation.Headline);
  if AExplanation.Detail <> '' then
  begin
    Parts := Parts + [AExplanation.Detail];
  end;
  if AHeader <> '' then
  begin
    Parts := Parts + [AHeader];
  end;
  if AExplanation.Lines <> nil then
  begin
    Parts := Parts + [TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvCopyChecked)];
    for Line in AExplanation.Lines do
    begin
      Parts := Parts + ['  ' + TAtlasDebugBannerLine.MarkText(Line.Mark) + ' ' + Line.Text];
    end;
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
  Result.Headline := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvAnalysing);
end;

class function TAtlasAvTexts.Failed(const AReason, AHeader: string): TAtlasDebugBannerExplanation;
begin
  Result := Default(TAtlasDebugBannerExplanation);
  Result.Active := True;
  Result.HeadlineMark := TAtlasDebugBannerMark.Neutral;
  Result.Headline := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvAmbiguous);
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
  begin
    Value := 'nil';
  end;
  case Check.State of
    TAtlasAvCheckState.Ok:
      Result := TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Ok, Check.Expression + ' = ' + Value);
    TAtlasAvCheckState.NilValue:
      Result := TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Bad, Check.Expression + ' = ' + Value);
    TAtlasAvCheckState.Freed:
      Result := TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Bad, Check.Expression + ' = ' + Value + ' (' +
        TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvStateFreed) + ')');
    TAtlasAvCheckState.Invalid:
      Result := TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Bad, Check.Expression + ' = ' + Value + ' (' +
        TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvStateInvalid) + ')');
    TAtlasAvCheckState.OutOfRange:
      Result := TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Bad, Check.Expression + ' = ' + Value + ' (' +
        TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvStateOutOfRange) + ')');
    TAtlasAvCheckState.NotReached:
      Result := TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Neutral, Check.Expression + ': ' +
        TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvStateNotReached));
    TAtlasAvCheckState.Failed:
      Result := TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Neutral, Check.Expression + ': ' +
        TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvStateFailed));
  else
    // Nicht ausgewertet: wegen eines Aufrufs ohne allowCalls oder weil die Prüfung abbrach.
    if AAnalysis.LinkOf(AIndex).Call and not AAnalysis.AllowCalls then
    begin
      Result := TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Neutral, Check.Expression + ': ' +
        TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvStateCall));
    end
    else
    begin
      Result := TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Neutral, Check.Expression + ': ' +
        TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvStateNotEvaluated));
    end;
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
  begin
    Result.HeadlineMark := TAtlasDebugBannerMark.Bad;
  end
  else
  begin
    Result.HeadlineMark := TAtlasDebugBannerMark.Neutral;
  end;
  if (AAnalysis.Chains.Statements > 1) and not Verdict.HasCulprit then
  begin
    if Result.Detail <> '' then
    begin
      Result.Detail := Result.Detail + ' ' + #$00B7 + ' ' +
        TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugAvStatements, [AAnalysis.Chains.Statements]);
    end
    else
    begin
      Result.Detail := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugAvStatements, [AAnalysis.Chains.Statements]);
    end;
  end;
  for Index := 0 to High(AAnalysis.Checks) do
  begin
    Result.Lines := Result.Lines + [CheckLine(AAnalysis, Index)];
  end;
  // „Wo wird X zugewiesen?“ nur für ein benanntes Glied; Self wird nicht zugewiesen.
  if ACanWhere and Verdict.HasCulprit and (Verdict.Culprit.Name <> '') and
    not SameText(Verdict.Culprit.Name, 'Self') then
  begin
    Result.WhereName := Verdict.Culprit.Name;
  end;
  if ACanEvaluate then
  begin
    if Verdict.HasCulprit then
    begin
      Result.EvaluateExpression := Verdict.Culprit.Expression;
    end
    else if AAnalysis.Chains.Chains <> nil then
    begin
      Result.EvaluateExpression := AAnalysis.Chains.Chains[0].Text;
    end;
  end;
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
  begin
    Text := Text + ' ' + #$00B7 + ' ' + AExplanation.Detail;
  end;
  Result := TArray<string>.Create(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugAvMessage, [APlace, Text]));
  for Line in AExplanation.Lines do
  begin
    Result := Result + ['  ' + TAtlasDebugBannerLine.MarkText(Line.Mark) + ' ' + Line.Text];
  end;
end;

end.
