unit Atlas.UI.Debug.AccessViolation;

// Zugriffsverletzung erklären (#865), Texte: aus dem Ergebnis von TAtlasAvAnalysis die Erklärung für die
// Exception-Leiste (Ergebniszeile, Feld bzw. Füllmuster, geprüfte Glieder mit ✓/✗), den Text für „Erklärung
// kopieren“ und die Zeilen für die Meldungen, wenn keine Leiste steht (debug.exceptionBanner aus).
// Modul der Fehleradresse (#1820): „Adresse liegt in vcl290.bpl (RTL/VCL)“ als Zusatz zur Erklärung bzw. als
// eigene Erklärung, wenn der Fehler nicht in eigenem Code liegt, dann mit der letzten eigenen Stelle.

interface

uses
  System.SysUtils,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.Modules,
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
    /// <summary>„Adresse liegt in …“ zum Modul der Fehleradresse (#1820); '' ohne bekanntes Modul.</summary>
    class function ModuleText(const AModule: TAtlasDebugFaultModule): string; static;
    /// <summary>„zuletzt in deinem Code: Unit1.pas:42 (TForm1.Button1Click)“ bzw. „kein eigener Code …“.</summary>
    class function OwnFrameText(const AModule: TAtlasDebugFaultModule; const AFrames: TAtlasDebugFrames): string;
      static;
    /// <summary>Erklärung nur mit dem Modul, wenn der Halt nicht in eigenem Code steht (#1820): Modul als
    /// Ergebniszeile, die letzte eigene Stelle dahinter; Active = False ohne bekanntes Modul.</summary>
    class function ModuleOnly(const AModule: TAtlasDebugFaultModule; const AFrames: TAtlasDebugFrames;
      const AHeader: string): TAtlasDebugBannerExplanation; static;
    /// <summary>Fertige Erklärung um den Text zum Modul (ModuleText) ergänzen: hinter dem Detail und im kopierten
    /// Text; '' lässt sie unverändert.</summary>
    class function WithModule(const AExplanation: TAtlasDebugBannerExplanation;
      const AModuleText: string): TAtlasDebugBannerExplanation; static;
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
    (AMessage.Address < TAtlasAvAnalysis.cNearNil) then
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
  mParts: TArray<string>;
  mLine: TAtlasDebugBannerLine;
begin
  mParts := TArray<string>.Create(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvCopyHeader), AExplanation.Headline);
  if AExplanation.Detail <> '' then
  begin
    mParts := mParts + [AExplanation.Detail];
  end;
  if AHeader <> '' then
  begin
    mParts := mParts + [AHeader];
  end;
  if AExplanation.Lines <> nil then
  begin
    mParts := mParts + [TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvCopyChecked)];
    for mLine in AExplanation.Lines do
    begin
      mParts := mParts + ['  ' + TAtlasDebugBannerLine.MarkText(mLine.Mark) + ' ' + mLine.Text];
    end;
  end;
  Result := string.Join(sLineBreak, mParts);
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
  mCheck: TAtlasAvCheck;
  mValue: string;
begin
  mCheck := AAnalysis.Checks[AIndex];
  mValue := mCheck.Value;
  if mCheck.State = TAtlasAvCheckState.NilValue then
  begin
    mValue := 'nil';
  end;
  case mCheck.State of
    TAtlasAvCheckState.Ok:
      Result := TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Ok, mCheck.Expression + ' = ' + mValue);
    TAtlasAvCheckState.NilValue:
      Result := TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Bad, mCheck.Expression + ' = ' + mValue);
    TAtlasAvCheckState.Freed:
      Result := TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Bad, mCheck.Expression + ' = ' + mValue + ' (' +
        TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvStateFreed) + ')');
    TAtlasAvCheckState.Invalid:
      Result := TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Bad, mCheck.Expression + ' = ' + mValue + ' (' +
        TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvStateInvalid) + ')');
    TAtlasAvCheckState.OutOfRange:
      Result := TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Bad, mCheck.Expression + ' = ' + mValue + ' (' +
        TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvStateOutOfRange) + ')');
    TAtlasAvCheckState.NotReached:
      Result := TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Neutral, mCheck.Expression + ': ' +
        TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvStateNotReached));
    TAtlasAvCheckState.Failed:
      Result := TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Neutral, mCheck.Expression + ': ' +
        TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvStateFailed));
  else
    // Nicht ausgewertet: wegen eines Aufrufs ohne allowCalls oder weil die Prüfung abbrach.
    if AAnalysis.LinkOf(AIndex).Call and not AAnalysis.AllowCalls then
    begin
      Result := TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Neutral, mCheck.Expression + ': ' +
        TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvStateCall));
    end
    else
    begin
      Result := TAtlasDebugBannerLine.Create(TAtlasDebugBannerMark.Neutral, mCheck.Expression + ': ' +
        TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvStateNotEvaluated));
    end;
  end;
end;

class function TAtlasAvTexts.FromAnalysis(AAnalysis: TAtlasAvAnalysis; ACanWhere, ACanEvaluate: Boolean;
  const AHeader: string): TAtlasDebugBannerExplanation;
var
  mVerdict: TAtlasAvVerdict;
  mIndex: Integer;
  mDetail: string;
begin
  Result := Default(TAtlasDebugBannerExplanation);
  Result.Active := True;
  mVerdict := AAnalysis.Verdict;
  // Die Zeigergröße steckt in der Erkennung; für den Text genügt die größere Musterliste.
  Result.Headline := HeadlineOf(mVerdict, AAnalysis.AccessMessage, 8, mDetail);
  Result.Detail := mDetail;
  if mVerdict.HasCulprit or (mVerdict.Kind = TAtlasAvVerdictKind.FreedMemory) then
  begin
    Result.HeadlineMark := TAtlasDebugBannerMark.Bad;
  end
  else
  begin
    Result.HeadlineMark := TAtlasDebugBannerMark.Neutral;
  end;
  if (AAnalysis.Chains.Statements > 1) and not mVerdict.HasCulprit then
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
  for mIndex := 0 to High(AAnalysis.Checks) do
  begin
    Result.Lines := Result.Lines + [CheckLine(AAnalysis, mIndex)];
  end;
  // „Wo wird X zugewiesen?“ nur für ein benanntes Glied; Self wird nicht zugewiesen.
  if ACanWhere and mVerdict.HasCulprit and (mVerdict.Culprit.Name <> '') and
    not SameText(mVerdict.Culprit.Name, 'Self') then
  begin
    Result.WhereName := mVerdict.Culprit.Name;
  end;
  if ACanEvaluate then
  begin
    if mVerdict.HasCulprit then
    begin
      Result.EvaluateExpression := mVerdict.Culprit.Expression;
    end
    else if AAnalysis.Chains.Chains <> nil then
    begin
      Result.EvaluateExpression := AAnalysis.Chains.Chains[0].Text;
    end;
  end;
  Result.CopyText := CopyTextOf(Result, AHeader);
end;

class function TAtlasAvTexts.ModuleText(const AModule: TAtlasDebugFaultModule): string;
begin
  Result := '';
  if not AModule.Known then
  begin
    Exit;
  end;
  case AModule.Kind of
    TAtlasDebugModuleKind.ProgramFile:
      Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugAvModuleProgram, [AModule.Name]);
    TAtlasDebugModuleKind.Runtime:
      Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugAvModuleRuntime, [AModule.Name]);
    TAtlasDebugModuleKind.OperatingSystem:
      Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugAvModuleSystem, [AModule.Name]);
    TAtlasDebugModuleKind.Foreign:
      if AModule.NoDebugInfo then
      begin
        Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugAvModuleNoDebugInfo, [AModule.Name]);
      end
      else
      begin
        Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugAvModuleForeign, [AModule.Name]);
      end;
    TAtlasDebugModuleKind.Unknown:
      Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugAvModuleForeign, [AModule.Name]);
  end;
end;

class function TAtlasAvTexts.OwnFrameText(const AModule: TAtlasDebugFaultModule;
  const AFrames: TAtlasDebugFrames): string;
var
  mFrame: TAtlasDebugFrame;
begin
  if (AModule.OwnFrame < 0) or (AModule.OwnFrame > High(AFrames)) then
  begin
    Exit(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvModuleNoOwnFrame));
  end;
  mFrame := AFrames[AModule.OwnFrame];
  Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugAvModuleOwnFrame, [ExtractFileName(mFrame.FileName),
    mFrame.Line, mFrame.Routine]);
end;

class function TAtlasAvTexts.ModuleOnly(const AModule: TAtlasDebugFaultModule; const AFrames: TAtlasDebugFrames;
  const AHeader: string): TAtlasDebugBannerExplanation;
begin
  Result := Default(TAtlasDebugBannerExplanation);
  Result.Headline := ModuleText(AModule);
  if Result.Headline = '' then
  begin
    Exit;
  end;
  Result.Active := True;
  Result.HeadlineMark := TAtlasDebugBannerMark.Neutral;
  // Im eigenen Programm, aber ohne Quelltext am Halt: die letzte eigene Stelle hilft genauso.
  Result.Detail := OwnFrameText(AModule, AFrames);
  Result.CopyText := CopyTextOf(Result, AHeader);
end;

class function TAtlasAvTexts.WithModule(const AExplanation: TAtlasDebugBannerExplanation;
  const AModuleText: string): TAtlasDebugBannerExplanation;
begin
  Result := AExplanation;
  if (AModuleText = '') or not Result.Active or Result.Busy then
  begin
    Exit;
  end;
  if Result.Detail <> '' then
  begin
    Result.Detail := Result.Detail + ' ' + #$00B7 + ' ' + AModuleText;
  end
  else
  begin
    Result.Detail := AModuleText;
  end;
  if Result.CopyText <> '' then
  begin
    Result.CopyText := Result.CopyText + sLineBreak + AModuleText;
  end;
end;


class function TAtlasAvTexts.MessageLines(const AExplanation: TAtlasDebugBannerExplanation;

  const APlace: string): TArray<string>;
var
  mText: string;
  mLine: TAtlasDebugBannerLine;
begin
  mText := AExplanation.Headline;
  if AExplanation.Detail <> '' then
  begin
    mText := mText + ' ' + #$00B7 + ' ' + AExplanation.Detail;
  end;
  Result := TArray<string>.Create(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugAvMessage, [APlace, mText]));
  for mLine in AExplanation.Lines do
  begin
    Result := Result + ['  ' + TAtlasDebugBannerLine.MarkText(mLine.Mark) + ' ' + mLine.Text];
  end;
end;

end.
