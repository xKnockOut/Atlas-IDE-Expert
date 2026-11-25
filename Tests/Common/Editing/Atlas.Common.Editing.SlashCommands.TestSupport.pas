unit Atlas.Common.Editing.SlashCommands.TestSupport;

// Gemeinsame Hilfen der Tests zu Schrägstrich-Befehlen: Befehl in einer Zeile ausführen, die Änderungen anwenden
// und Probleme lesen.

interface

type
  TSlashTest = record
  public
    /// <summary>Führt den Befehl in Zeile ALine (ab 0) aus und wendet die Änderungen an; prüft, dass er passt.
    /// </summary>
    class function Expand(const AText: string; ALine: Integer): string; static;
    /// <summary>Wie Expand, '' wenn der Befehl nicht passt.</summary>
    class function ExpandOrEmpty(const AText: string; ALine: Integer): string; overload; static;
    /// <summary>Wie ExpandOrEmpty, für die Delphi-Version AVersion ('' = aktuell).</summary>
    class function ExpandOrEmpty(const AText: string; ALine: Integer; const AVersion: string): string; overload;
      static;
    /// <summary>Meldung des einzigen Problems in AText; prüft, dass es genau eins gibt.</summary>
    class function ProblemOf(const AText: string): string; static;
  end;

implementation

uses
  DUnitX.TestFramework,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Tests.TextEdits,
  Atlas.Common.Documents.Contract;

{ TSlashTest }

class function TSlashTest.Expand(const AText: string; ALine: Integer): string;
var
  mEdits: TArray<TTextEdit>;
begin
  Assert.IsTrue(TSlashCommandRegistry.Shared.AfterEnter(AText, TTextPosition.Create(ALine + 1, 0), nil, nil, mEdits),
    AText);
  Result := TTestEdits.Apply(AText, mEdits);
end;

class function TSlashTest.ExpandOrEmpty(const AText: string; ALine: Integer): string;
var
  mEdits: TArray<TTextEdit>;
begin
  Result := '';
  if TSlashCommandRegistry.Shared.AfterEnter(AText, TTextPosition.Create(ALine + 1, 0), nil, nil, mEdits) then
  begin
    Result := TTestEdits.Apply(AText, mEdits);
  end;
end;

class function TSlashTest.ExpandOrEmpty(const AText: string; ALine: Integer; const AVersion: string): string;
var
  mEdits: TArray<TTextEdit>;
begin
  Result := '';
  if TSlashCommandRegistry.Shared.AfterEnter(AText, TTextPosition.Create(ALine + 1, 0),
    TSlashEnvironment.Create(nil, nil, nil, AVersion, '', nil), mEdits) then
  begin
    Result := TTestEdits.Apply(AText, mEdits);
  end;
end;

class function TSlashTest.ProblemOf(const AText: string): string;
var
  mProblems: TArray<TSlashProblem>;
begin
  mProblems := TSlashCommandRegistry.Shared.Problems(AText, nil);
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Result := mProblems[0].Message;
end;

end.
