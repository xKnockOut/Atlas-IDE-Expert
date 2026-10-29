unit Atlas.Common.Rules.FormatOutput;

// Ausgabe von --format-check und --format-write (#1358) als Text, JSON oder
// vereinigter Diff, dazu der Exit-Code. Zeilen beginnen überall bei 1.
//   Text  je betroffene Datei die ersten Abweichungen mit Zeile und Art,
//         Syntaxfehler (nicht formatiert) und instabile Formatierung
//   Json  alle Abweichungen; nur Dateien mit Abweichung oder Problem, dazu
//         die Zähler über alle geprüften Dateien (AFiles enthält alle)
//   Diff  vereinigter Diff („diff -u“) aller geänderten Dateien; Probleme
//         nennt Problems für stderr
// Exit-Code: Bei der Prüfung 1, sobald eine Datei abweicht, einen
// Syntaxfehler hat oder nicht stabil formatiert; beim Schreiben 1 nur bei
// Syntaxfehlern und instabiler Formatierung. Ein Schreibfehler ergibt 3.

interface

uses
  System.SysUtils,
  Atlas.Common.Editing.FormatCheck;

type
  {$SCOPEDENUMS ON}
  TFormatOutputKind = (Text, Json, Diff);
  {$SCOPEDENUMS OFF}

  TFormattedFile = record
    /// <summary>Pfad relativ zum Ziel wie bei --check.</summary>
    Path: string;
    Outcome: TFormatOutcome;
    /// <summary>Mit --format-write geschrieben.</summary>
    Written: Boolean;
    /// <summary>Schreiben gescheitert: Grund; '' sonst.</summary>
    Error: string;
    class function Create(const APath: string; const AOutcome: TFormatOutcome): TFormattedFile; static;
    /// <summary>Weicht ab, hat einen Syntaxfehler, ist instabil oder wurde nicht geschrieben.</summary>
    function NeedsAttention: Boolean;
  end;

  TFormatOutput = class
  public const
    /// <summary>So viele Abweichungen je Datei zeigt die Textausgabe.</summary>
    cShownPerFile = 5;
    /// <summary>Umgebung je Block im Diff.</summary>
    cDiffContext = 3;
  public
    /// <summary>Ausgabe für stdout; AWrite = --format-write.</summary>
    class function Render(const AFiles: TArray<TFormattedFile>; AKind: TFormatOutputKind; AWrite: Boolean): string;
      static;
    /// <summary>Syntaxfehler, instabile Dateien und Schreibfehler als Zeilen (für stderr bei Diff).</summary>
    class function Problems(const AFiles: TArray<TFormattedFile>): TArray<string>; static;
    /// <summary>Zusammenfassung für stderr, z. B. "Formatierung: 2 von 10 Dateien weichen ab".</summary>
    class function Summary(const AFiles: TArray<TFormattedFile>; AWrite: Boolean): string; static;
    /// <summary>Exit-Code nach dem Kopf der Unit.</summary>
    class function ExitCode(const AFiles: TArray<TFormattedFile>; AWrite: Boolean): Integer; static;
  end;

implementation

uses
  System.Math,
  Atlas.Text.Lines,
  Atlas.Text.Diff,
  Atlas.Common.Rules.Output;

{ TFormattedFile }

class function TFormattedFile.Create(const APath: string; const AOutcome: TFormatOutcome): TFormattedFile;
begin
  Result.Path := APath;
  Result.Outcome := AOutcome;
  Result.Written := False;
  Result.Error := '';
end;

function TFormattedFile.NeedsAttention: Boolean;
begin
  Result := Outcome.Changed or Outcome.HasSyntaxError or not Outcome.Stable or (Error <> '');
end;

{ TFormatOutput }

function SlashPath(const APath: string): string;
begin
  Result := StringReplace(APath, '\', '/', [rfReplaceAll]);
end;

function SyntaxLine(const AFile: TFormattedFile): string;
begin
  Result := Format('%s(%d,%d): Syntaxfehler, nicht formatiert: %s', [AFile.Path,
    AFile.Outcome.SyntaxError.StartPos.Line + 1, AFile.Outcome.SyntaxError.StartPos.Character + 1,
    AFile.Outcome.SyntaxError.Message]);
end;

function UnstableLine(const AFile: TFormattedFile): string;
begin
  Result := Format('%s: Formatierung nicht stabil, ein zweiter Lauf ändert erneut', [AFile.Path]);
end;

class function TFormatOutput.Problems(const AFiles: TArray<TFormattedFile>): TArray<string>;
var
  mFile: TFormattedFile;
begin
  Result := nil;
  for mFile in AFiles do
  begin
    if mFile.Outcome.HasSyntaxError then
      Result := Result + [SyntaxLine(mFile)];
    if not mFile.Outcome.Stable then
      Result := Result + [UnstableLine(mFile)];
    if mFile.Error <> '' then
      Result := Result + [Format('%s: nicht geschrieben: %s', [mFile.Path, mFile.Error])];
  end;
end;

function RenderText(const AFiles: TArray<TFormattedFile>; AWrite: Boolean): string;
var
  mBuilder: TStringBuilder;
  mFile: TFormattedFile;
  mIndex, mCount: Integer;
  mLine: string;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mFile in AFiles do
    begin
      if mFile.Outcome.HasSyntaxError then
        mBuilder.AppendLine(SyntaxLine(mFile));
      mCount := Length(mFile.Outcome.Deviations);
      if mFile.Outcome.Changed then
      begin
        if AWrite and mFile.Written then
          mBuilder.AppendLine(Format('%s: formatiert (%d Abweichungen)', [mFile.Path, mCount]))
        else if AWrite then
          mBuilder.AppendLine(Format('%s: nicht geschrieben: %s', [mFile.Path, mFile.Error]))
        else
        begin
          mBuilder.AppendLine(Format('%s: %d Abweichungen', [mFile.Path, mCount]));
          for mIndex := 0 to Min(mCount, TFormatOutput.cShownPerFile) - 1 do
          begin
            mLine := Format('  Zeile %d: %s', [mFile.Outcome.Deviations[mIndex].Line + 1,
              mFile.Outcome.Deviations[mIndex].Message]);
            mBuilder.AppendLine(mLine);
          end;
          if mCount > TFormatOutput.cShownPerFile then
            mBuilder.AppendLine(Format('  … und %d weitere (alle mit --format json)',
              [mCount - TFormatOutput.cShownPerFile]));
        end;
      end;
      if not mFile.Outcome.Stable then
        mBuilder.AppendLine(UnstableLine(mFile));
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

function RenderJson(const AFiles: TArray<TFormattedFile>; AWrite: Boolean): string;
var
  mBuilder: TStringBuilder;
  mFile: TFormattedFile;
  mDeviation: TFormatDeviation;
  mFirstFile, mFirstDeviation: Boolean;
  mChanged, mSyntax, mUnstable, mWritten: Integer;
begin
  mChanged := 0;
  mSyntax := 0;
  mUnstable := 0;
  mWritten := 0;
  mBuilder := TStringBuilder.Create;
  try
    if AWrite then
      mBuilder.Append('{"mode":"write","files":[')
    else
      mBuilder.Append('{"mode":"check","files":[');
    mFirstFile := True;
    for mFile in AFiles do
    begin
      if mFile.Outcome.Changed then
        Inc(mChanged);
      if mFile.Outcome.HasSyntaxError then
        Inc(mSyntax);
      if not mFile.Outcome.Stable then
        Inc(mUnstable);
      if mFile.Written then
        Inc(mWritten);
      if not mFile.NeedsAttention then
        Continue;
      if not mFirstFile then
        mBuilder.Append(',');
      mFirstFile := False;
      mBuilder.Append('{"path":').Append(TFindingsOutput.JsonString(SlashPath(mFile.Path)));
      mBuilder.Append(',"changed":').Append(LowerCase(BoolToStr(mFile.Outcome.Changed, True)));
      mBuilder.Append(',"stable":').Append(LowerCase(BoolToStr(mFile.Outcome.Stable, True)));
      mBuilder.Append(',"written":').Append(LowerCase(BoolToStr(mFile.Written, True)));
      if mFile.Error <> '' then
        mBuilder.Append(',"error":').Append(TFindingsOutput.JsonString(mFile.Error));
      if mFile.Outcome.HasSyntaxError then
        mBuilder.Append(',"syntaxError":{"line":').Append(mFile.Outcome.SyntaxError.StartPos.Line + 1)
          .Append(',"column":').Append(mFile.Outcome.SyntaxError.StartPos.Character + 1)
          .Append(',"message":').Append(TFindingsOutput.JsonString(mFile.Outcome.SyntaxError.Message)).Append('}');
      mBuilder.Append(',"deviations":[');
      mFirstDeviation := True;
      for mDeviation in mFile.Outcome.Deviations do
      begin
        if not mFirstDeviation then
          mBuilder.Append(',');
        mFirstDeviation := False;
        mBuilder.Append('{"line":').Append(mDeviation.Line + 1);
        mBuilder.Append(',"kind":').Append(TFindingsOutput.JsonString(TFormatCheck.KindName(mDeviation.Kind)));
        mBuilder.Append(',"message":').Append(TFindingsOutput.JsonString(mDeviation.Message)).Append('}');
      end;
      mBuilder.Append(']}');
    end;
    mBuilder.Append('],"summary":{"files":').Append(Length(AFiles));
    mBuilder.Append(',"changed":').Append(mChanged);
    mBuilder.Append(',"syntaxErrors":').Append(mSyntax);
    mBuilder.Append(',"unstable":').Append(mUnstable);
    mBuilder.Append(',"written":').Append(mWritten).Append('}}');
    Result := mBuilder.ToString + sLineBreak;
  finally
    mBuilder.Free;
  end;
end;

function RenderDiff(const AFiles: TArray<TFormattedFile>): string;
var
  mBuilder: TStringBuilder;
  mFile: TFormattedFile;
  mLine, mPath: string;
  mOld, mNew: TArray<string>;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mFile in AFiles do
    begin
      if not mFile.Outcome.Changed then
        Continue;
      mPath := SlashPath(mFile.Path);
      mOld := TTextLines.SplitLines(mFile.Outcome.Original);
      mNew := TTextLines.SplitLines(mFile.Outcome.Formatted);
      // Enden beide mit einem Umbruch, ist die leere letzte Zeile keine Zeile (wie bei diff -u).
      if (Length(mOld) > 1) and (Length(mNew) > 1) and (mOld[High(mOld)] = '') and (mNew[High(mNew)] = '') then
      begin
        SetLength(mOld, Length(mOld) - 1);
        SetLength(mNew, Length(mNew) - 1);
      end;
      for mLine in TTextDiff.Unified('a/' + mPath, 'b/' + mPath, mOld, mNew, TFormatOutput.cDiffContext) do
        mBuilder.Append(mLine).Append(#10);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TFormatOutput.Render(const AFiles: TArray<TFormattedFile>; AKind: TFormatOutputKind;
  AWrite: Boolean): string;
begin
  case AKind of
    TFormatOutputKind.Json:
      Result := RenderJson(AFiles, AWrite);
    TFormatOutputKind.Diff:
      Result := RenderDiff(AFiles);
  else
    Result := RenderText(AFiles, AWrite);
  end;
end;

class function TFormatOutput.Summary(const AFiles: TArray<TFormattedFile>; AWrite: Boolean): string;
var
  mFile: TFormattedFile;
  mChanged, mWritten, mSyntax: Integer;
begin
  mChanged := 0;
  mWritten := 0;
  mSyntax := 0;
  for mFile in AFiles do
  begin
    if mFile.Outcome.Changed then
      Inc(mChanged);
    if mFile.Written then
      Inc(mWritten);
    if mFile.Outcome.HasSyntaxError then
      Inc(mSyntax);
  end;
  if AWrite then
    Result := Format('Formatierung: %d von %d Dateien geschrieben', [mWritten, Length(AFiles)])
  else
    Result := Format('Formatierung: %d von %d Dateien weichen ab', [mChanged, Length(AFiles)]);
  if mSyntax > 0 then
    Result := Result + Format(', %d mit Syntaxfehlern nicht formatiert', [mSyntax]);
end;

class function TFormatOutput.ExitCode(const AFiles: TArray<TFormattedFile>; AWrite: Boolean): Integer;
var
  mFile: TFormattedFile;
begin
  Result := TFindingsOutput.ExitClean;
  for mFile in AFiles do
  begin
    if mFile.Error <> '' then
      Exit(TFindingsOutput.ExitFailure);
    if mFile.Outcome.HasSyntaxError or not mFile.Outcome.Stable or (not AWrite and mFile.Outcome.Changed) then
      Result := TFindingsOutput.ExitFindings;
  end;
end;

end.
