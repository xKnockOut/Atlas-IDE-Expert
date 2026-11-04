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
    begin
      Result := Result + [SyntaxLine(mFile)];
    end;
    if not mFile.Outcome.Stable then
    begin
      Result := Result + [UnstableLine(mFile)];
    end;
    if mFile.Error <> '' then
    begin
      Result := Result + [Format('%s: nicht geschrieben: %s', [mFile.Path, mFile.Error])];
    end;
  end;
end;

/// <summary>Zeilen einer geänderten Datei: formatiert, nicht geschrieben oder die ersten Abweichungen.</summary>
procedure AppendChanged(ABuilder: TStringBuilder; const AFile: TFormattedFile; AWrite: Boolean);
var
  mIndex, mCount: Integer;
begin
  mCount := Length(AFile.Outcome.Deviations);
  if AWrite and AFile.Written then
  begin
    ABuilder.AppendLine(Format('%s: formatiert (%d Abweichungen)', [AFile.Path, mCount]));
    Exit;
  end;
  if AWrite then
  begin
    ABuilder.AppendLine(Format('%s: nicht geschrieben: %s', [AFile.Path, AFile.Error]));
    Exit;
  end;
  ABuilder.AppendLine(Format('%s: %d Abweichungen', [AFile.Path, mCount]));
  for mIndex := 0 to Min(mCount, TFormatOutput.cShownPerFile) - 1 do
  begin
    ABuilder.AppendLine(Format('  Zeile %d: %s', [AFile.Outcome.Deviations[mIndex].Line + 1,
      AFile.Outcome.Deviations[mIndex].Message]));
  end;
  if mCount > TFormatOutput.cShownPerFile then
  begin
    ABuilder.AppendLine(Format('  … und %d weitere (alle mit --format json)', [mCount - TFormatOutput.cShownPerFile]));
  end;
end;

function RenderText(const AFiles: TArray<TFormattedFile>; AWrite: Boolean): string;
var
  mBuilder: TStringBuilder;
  mFile: TFormattedFile;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mFile in AFiles do
    begin
      if mFile.Outcome.HasSyntaxError then
      begin
        mBuilder.AppendLine(SyntaxLine(mFile));
      end;
      if mFile.Outcome.Changed then
      begin
        AppendChanged(mBuilder, mFile, AWrite);
      end;
      if not mFile.Outcome.Stable then
      begin
        mBuilder.AppendLine(UnstableLine(mFile));
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

function JsonBool(AValue: Boolean): string;
begin
  Result := LowerCase(BoolToStr(AValue, True));
end;

/// <summary>Eine Datei als JSON-Objekt mit Fehler, Syntaxfehler und allen Abweichungen.</summary>
procedure AppendJsonFile(ABuilder: TStringBuilder; const AFile: TFormattedFile);
var
  mDeviation: TFormatDeviation;
  mFirst: Boolean;
begin
  ABuilder.Append('{"path":').Append(TFindingsOutput.JsonString(SlashPath(AFile.Path)));
  ABuilder.Append(',"changed":').Append(JsonBool(AFile.Outcome.Changed));
  ABuilder.Append(',"stable":').Append(JsonBool(AFile.Outcome.Stable));
  ABuilder.Append(',"written":').Append(JsonBool(AFile.Written));
  if AFile.Error <> '' then
  begin
    ABuilder.Append(',"error":').Append(TFindingsOutput.JsonString(AFile.Error));
  end;
  if AFile.Outcome.HasSyntaxError then
  begin
    ABuilder.Append(',"syntaxError":{"line":').Append(AFile.Outcome.SyntaxError.StartPos.Line + 1)
      .Append(',"column":').Append(AFile.Outcome.SyntaxError.StartPos.Character + 1)
      .Append(',"message":').Append(TFindingsOutput.JsonString(AFile.Outcome.SyntaxError.Message)).Append('}');
  end;
  ABuilder.Append(',"deviations":[');
  mFirst := True;
  for mDeviation in AFile.Outcome.Deviations do
  begin
    if not mFirst then
    begin
      ABuilder.Append(',');
    end;
    mFirst := False;
    ABuilder.Append('{"line":').Append(mDeviation.Line + 1);
    ABuilder.Append(',"kind":').Append(TFindingsOutput.JsonString(TFormatCheck.KindName(mDeviation.Kind)));
    ABuilder.Append(',"message":').Append(TFindingsOutput.JsonString(mDeviation.Message)).Append('}');
  end;
  ABuilder.Append(']}');
end;

/// <summary>"summary" mit den Zählern über alle Dateien.</summary>
procedure AppendJsonSummary(ABuilder: TStringBuilder; const AFiles: TArray<TFormattedFile>);
var
  mFile: TFormattedFile;
  mChanged, mSyntax, mUnstable, mWritten: Integer;
begin
  mChanged := 0;
  mSyntax := 0;
  mUnstable := 0;
  mWritten := 0;
  for mFile in AFiles do
  begin
    Inc(mChanged, Ord(mFile.Outcome.Changed));
    Inc(mSyntax, Ord(mFile.Outcome.HasSyntaxError));
    Inc(mUnstable, Ord(not mFile.Outcome.Stable));
    Inc(mWritten, Ord(mFile.Written));
  end;
  ABuilder.Append('"summary":{"files":').Append(Length(AFiles));
  ABuilder.Append(',"changed":').Append(mChanged);
  ABuilder.Append(',"syntaxErrors":').Append(mSyntax);
  ABuilder.Append(',"unstable":').Append(mUnstable);
  ABuilder.Append(',"written":').Append(mWritten).Append('}');
end;

function RenderJson(const AFiles: TArray<TFormattedFile>; AWrite: Boolean): string;
var
  mBuilder: TStringBuilder;
  mFile: TFormattedFile;
  mFirst: Boolean;
begin
  mBuilder := TStringBuilder.Create;
  try
    if AWrite then
    begin
      mBuilder.Append('{"mode":"write","files":[');
    end
    else
    begin
      mBuilder.Append('{"mode":"check","files":[');
    end;
    mFirst := True;
    for mFile in AFiles do
    begin
      if mFile.NeedsAttention then
      begin
        if not mFirst then
        begin
          mBuilder.Append(',');
        end;
        mFirst := False;
        AppendJsonFile(mBuilder, mFile);
      end;
    end;
    mBuilder.Append('],');
    AppendJsonSummary(mBuilder, AFiles);
    mBuilder.Append('}');
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
      begin
        Continue;
      end;
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
      begin
        mBuilder.Append(mLine).Append(#10);
      end;
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
    begin
      Inc(mChanged);
    end;
    if mFile.Written then
    begin
      Inc(mWritten);
    end;
    if mFile.Outcome.HasSyntaxError then
    begin
      Inc(mSyntax);
    end;
  end;
  if AWrite then
  begin
    Result := Format('Formatierung: %d von %d Dateien geschrieben', [mWritten, Length(AFiles)]);
  end
  else
  begin
    Result := Format('Formatierung: %d von %d Dateien weichen ab', [mChanged, Length(AFiles)]);
  end;
  if mSyntax > 0 then
  begin
    Result := Result + Format(', %d mit Syntaxfehlern nicht formatiert', [mSyntax]);
  end;
end;

class function TFormatOutput.ExitCode(const AFiles: TArray<TFormattedFile>; AWrite: Boolean): Integer;
var
  mFile: TFormattedFile;
begin
  Result := TFindingsOutput.ExitClean;
  for mFile in AFiles do
  begin
    if mFile.Error <> '' then
    begin
      Exit(TFindingsOutput.ExitFailure);
    end;
    if mFile.Outcome.HasSyntaxError or not mFile.Outcome.Stable or (not AWrite and mFile.Outcome.Changed) then
    begin
      Result := TFindingsOutput.ExitFindings;
    end;
  end;
end;

end.
