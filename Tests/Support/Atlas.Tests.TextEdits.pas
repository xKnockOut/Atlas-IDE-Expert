unit Atlas.Tests.TextEdits;

// Testhilfe: Textänderungen (TTextEdit, Korrekturen von Regeln) auf einen Text anwenden, um das Ergebnis mit dem
// erwarteten Text zu vergleichen. Viele Testunits hatten dafür eigene, wortgleiche Routinen.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract;

type
  TTestEdits = record
  public
    /// <summary>Offset (ab 0) der Position APosition in AText.</summary>
    class function Offset(const AText: string; const APosition: TTextPosition): Integer; static;
    /// <summary>
    ///   AText mit allen AEdits. Die Bereiche beziehen sich auf AText; angewendet wird von hinten nach vorn.
    ///   Einfügungen an derselben Stelle stehen danach in der Reihenfolge von AEdits.
    /// </summary>
    class function Apply(const AText: string; const AEdits: TArray<TTextEdit>): string; overload; static;
    /// <summary>AText mit der einen Änderung AEdit.</summary>
    class function Apply(const AText: string; const AEdit: TTextEdit): string; overload; static;
    /// <summary>AText mit allen Änderungen der Korrektur AFix.</summary>
    class function ApplyFix(const AText: string; const AFix: TRuleFix): string; static;
  end;

implementation

uses
  Atlas.Text.Lines;

{ TTestEdits }

class function TTestEdits.Offset(const AText: string; const APosition: TTextPosition): Integer;
begin
  Result := TLineTable.Build(AText).OffsetAt(APosition);
end;

class function TTestEdits.Apply(const AText: string; const AEdits: TArray<TTextEdit>): string;
var
  mLines: TLineTable;
  mStarts, mStops, mOrder: TArray<Integer>;
  mIndex, mInner, mSwap: Integer;
begin
  mLines := TLineTable.Build(AText);
  SetLength(mStarts, Length(AEdits));
  SetLength(mStops, Length(AEdits));
  SetLength(mOrder, Length(AEdits));
  for mIndex := 0 to High(AEdits) do
  begin
    mStarts[mIndex] := mLines.OffsetAt(AEdits[mIndex].Range.StartPos);
    mStops[mIndex] := mLines.OffsetAt(AEdits[mIndex].Range.EndPos);
    mOrder[mIndex] := mIndex;
  end;
  // Stabil sortiert: hinten zuerst, bei gleichem Anfang die spätere Änderung zuerst.
  for mIndex := 1 to High(mOrder) do
  begin
    mInner := mIndex;
    while (mInner > 0) and ((mStarts[mOrder[mInner - 1]] < mStarts[mOrder[mInner]]) or
      ((mStarts[mOrder[mInner - 1]] = mStarts[mOrder[mInner]]) and (mOrder[mInner - 1] < mOrder[mInner]))) do
    begin
      mSwap := mOrder[mInner - 1];
      mOrder[mInner - 1] := mOrder[mInner];
      mOrder[mInner] := mSwap;
      Dec(mInner);
    end;
  end;
  Result := AText;
  for mIndex in mOrder do
  begin
    Result := Copy(Result, 1, mStarts[mIndex]) + AEdits[mIndex].NewText + Copy(Result, mStops[mIndex] + 1, MaxInt);
  end;
end;

class function TTestEdits.Apply(const AText: string; const AEdit: TTextEdit): string;
var
  mEdits: TArray<TTextEdit>;
begin
  SetLength(mEdits, 1);
  mEdits[0] := AEdit;
  Result := Apply(AText, mEdits);
end;

class function TTestEdits.ApplyFix(const AText: string; const AFix: TRuleFix): string;
begin
  Result := Apply(AText, AFix.Edits);
end;

end.
