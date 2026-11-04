unit Atlas.Common.Rules.Builtin.Ownership.TryFinally;

// Korrektur der Besitzregeln (#948, #1047): eine Anweisung vor ein try setzen, die folgenden Anweisungen ihres
// Blocks einrücken und im finally freigeben. Gemeinsam für create-without-assignment und raw-memory-leak.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Zeilen und Zeilenumbruch der Datei samt Einrückungsstil, für <see cref="Wrap"/>.</summary>
  TTryFinallyWrap = record
    Lines: TArray<string>;
    LineBreak: string;
    Style: TFormatStyle;
    class function Create(const ALines: TArray<string>; const ALineBreak: string;
      const AStyle: TFormatStyle): TTryFinallyWrap; static;
    /// <summary>Setzt die Anweisung AStatement (eine Zeile, allein in ihrer Zeile, mit APrefix davor) vor ein
    /// try, rückt die folgenden Anweisungen ihres Blocks ein und gibt im finally mit AFree frei. False, wenn der
    /// Block sich so nicht umschließen lässt.</summary>
    function Wrap(AStatement: TSyntaxNode; const APrefix, AFree: string; out AEdit: TTextEdit): Boolean;
  private
    function EndsLine(ANode: TSyntaxNode): Boolean;
    function StandsAlone(AStatement: TSyntaxNode): Boolean;
    function WrappedText(AStatement: TSyntaxNode; ALastLine: Integer; const APrefix, AFree: string): string;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Editing.RoutineBody;

/// <summary>Letzte Anweisung desselben Blocks hinter AStatement, sonst AStatement selbst.</summary>
function LastSiblingOf(AStatement: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
begin
  Result := AStatement;
  for mIndex := 0 to AStatement.Parent.ChildCount - 1 do
  begin
    if AStatement.Parent[mIndex].StartOffset > AStatement.StartOffset then
    begin
      Result := AStatement.Parent[mIndex];
    end;
  end;
end;

{ TTryFinallyWrap }

class function TTryFinallyWrap.Create(const ALines: TArray<string>; const ALineBreak: string;
  const AStyle: TFormatStyle): TTryFinallyWrap;
begin
  Result.Lines := ALines;
  Result.LineBreak := ALineBreak;
  Result.Style := AStyle;
end;

/// <summary>Endet ANode seine Zeile (danach höchstens ein Semikolon)?</summary>
function TTryFinallyWrap.EndsLine(ANode: TSyntaxNode): Boolean;
var
  mRest: string;
begin
  Result := ANode.EndPos.Line <= High(Lines);
  if Result then
  begin
    mRest := Trim(Copy(Lines[ANode.EndPos.Line], ANode.EndPos.Character + 1, MaxInt));
    Result := (mRest = '') or (mRest = ';');
  end;
end;

/// <summary>Eine Anweisung in einem Block, einzeilig, allein in ihrer Zeile.</summary>
function TTryFinallyWrap.StandsAlone(AStatement: TSyntaxNode): Boolean;
begin
  Result := (AStatement.Parent <> nil) and (AStatement.Parent.Kind in [TSyntaxKind.Block, TSyntaxKind.TryStatement,
    TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptBlock]) and (AStatement.StartPos.Line = AStatement.EndPos.Line) and
    EndsLine(AStatement);
  Result := Result and (Trim(Copy(Lines[AStatement.StartPos.Line], 1, AStatement.StartPos.Character)) = '');
end;

function TTryFinallyWrap.WrappedText(AStatement: TSyntaxNode; ALastLine: Integer; const APrefix,
  AFree: string): string;
var
  mLine: Integer;
  mIndent, mUnitIndent: string;
begin
  mIndent := Copy(Lines[AStatement.StartPos.Line], 1, AStatement.StartPos.Character);
  mUnitIndent := TRoutineBody.IndentUnit(Style);
  Result := mIndent + APrefix + TrimLeft(Lines[AStatement.StartPos.Line]) + LineBreak + mIndent + 'try' + LineBreak;
  for mLine := AStatement.StartPos.Line + 1 to ALastLine do
  begin
    if Trim(Lines[mLine]) = '' then
    begin
      Result := Result + LineBreak;
    end
    else
    begin
      Result := Result + mUnitIndent + Lines[mLine] + LineBreak;
    end;
  end;
  Result := Result + mIndent + 'finally' + LineBreak + mIndent + mUnitIndent + AFree + LineBreak + mIndent +
    'end;' + LineBreak;
end;

function TTryFinallyWrap.Wrap(AStatement: TSyntaxNode; const APrefix, AFree: string; out AEdit: TTextEdit): Boolean;
var
  mLastSibling: TSyntaxNode;
begin
  // Die letzte folgende Anweisung desselben Blocks muss ihre Zeile allein beenden.
  mLastSibling := AStatement;
  Result := StandsAlone(AStatement);
  if Result then
  begin
    mLastSibling := LastSiblingOf(AStatement);
    Result := EndsLine(mLastSibling);
  end;
  if Result then
  begin
    AEdit := TTextEdit.Create(TTextRange.Create(AStatement.StartPos.Line, 0, mLastSibling.EndPos.Line + 1, 0),
      WrappedText(AStatement, mLastSibling.EndPos.Line, APrefix, AFree));
  end;
end;

end.
