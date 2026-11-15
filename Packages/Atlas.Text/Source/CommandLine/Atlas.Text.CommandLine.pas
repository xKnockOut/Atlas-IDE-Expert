unit Atlas.Text.CommandLine;

// Befehlszeilen für gestartete Programme (gemeinsam für Server und Plugin).
// Einzige Stelle, die Argumente in Anführungszeichen setzt: Weichen Kopien
// voneinander ab, kann ein Argument in zwei zerfallen oder ein fremdes
// Anführungszeichen den Rest der Zeile übernehmen.
// - Quote und Join nach den Regeln von CommandLineToArgvW (so lesen
//   Programme mit C-Laufzeit, git, svn, pwsh und dcc ihre Argumente):
//   Backslashes zählen nur vor einem Anführungszeichen, dort werden sie
//   verdoppelt, das Anführungszeichen selbst bekommt einen weiteren.
// - QuoteForParamStr für Delphi-Programme (ParamStr): Backslashes haben dort
//   keine Sonderrolle, ein Anführungszeichen im Wert lässt sich nicht
//   verlässlich schreiben und fällt darum weg.

interface

type
  TTextCommandLine = class
  public
    /// <summary>AArgument unverändert, wenn es weder leer ist noch Leerzeichen, Tabulator oder Anführungszeichen
    /// enthält; sonst in Anführungszeichen nach den Regeln von CommandLineToArgvW.</summary>
    class function Quote(const AArgument: string): string; static;
    /// <summary>AProgram und AArguments, jedes mit Quote, durch Leerzeichen getrennt (Befehlszeile für
    /// CreateProcess, das Programm als erstes Argument).</summary>
    class function Join(const AProgram: string; const AArguments: TArray<string>): string; static;
    /// <summary>AArguments mit Quote, durch Leerzeichen getrennt; '' ohne Argumente.</summary>
    class function JoinArguments(const AArguments: TArray<string>): string; static;
    /// <summary>Für Delphi-Programme: AArgument in Anführungszeichen, wenn es Leerzeichen oder Tabulatoren enthält,
    /// darin enthaltene Anführungszeichen fallen weg; sonst unverändert.</summary>
    class function QuoteForParamStr(const AArgument: string): string; static;
  end;

implementation

uses
  System.SysUtils;

class function TTextCommandLine.Quote(const AArgument: string): string;
var
  mBuilder: TStringBuilder;
  mIndex, mSlashes: Integer;
begin
  if (AArgument <> '') and (AArgument.IndexOfAny([' ', #9, '"']) < 0) then
  begin
    Exit(AArgument);
  end;
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('"');
    mSlashes := 0;
    for mIndex := 1 to Length(AArgument) do
    begin
      if AArgument[mIndex] = '\' then
      begin
        Inc(mSlashes);
        Continue;
      end;
      // Backslashes vor einem Anführungszeichen verdoppeln, das Zeichen selbst maskieren.
      if AArgument[mIndex] = '"' then
      begin
        mBuilder.Append(StringOfChar('\', mSlashes * 2 + 1));
      end
      else
      begin
        mBuilder.Append(StringOfChar('\', mSlashes));
      end;
      mSlashes := 0;
      mBuilder.Append(AArgument[mIndex]);
    end;
    // Backslashes vor dem schließenden Anführungszeichen verdoppeln.
    mBuilder.Append(StringOfChar('\', mSlashes * 2)).Append('"');
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TTextCommandLine.JoinArguments(const AArguments: TArray<string>): string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mIndex := 0 to High(AArguments) do
    begin
      if mIndex > 0 then
      begin
        mBuilder.Append(' ');
      end;
      mBuilder.Append(Quote(AArguments[mIndex]));
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TTextCommandLine.Join(const AProgram: string; const AArguments: TArray<string>): string;
begin
  Result := Quote(AProgram);
  if Length(AArguments) > 0 then
  begin
    Result := Result + ' ' + JoinArguments(AArguments);
  end;
end;

class function TTextCommandLine.QuoteForParamStr(const AArgument: string): string;
begin
  Result := AArgument;
  if (Pos(' ', AArgument) > 0) or (Pos(#9, AArgument) > 0) then
  begin
    Result := '"' + StringReplace(AArgument, '"', '', [rfReplaceAll]) + '"';
  end;
end;

end.
