unit Atlas.Common.Rules.Builtin.Declarations.Shared;

// Gemeinsame Hilfen der Deklarationsregeln (Atlas.Common.Rules.Builtin.Declarations und ihre Teilunits):
// Token zu einem Offset, Leerraum vor und hinter einer Stelle, Aufzählung "A, B und C", Name ohne Vorsatz.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract;

/// <summary>Erstes Token ab AOffset (Index), High + 1 ohne.</summary>
function TokenAtOffset(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
/// <summary>Steht vor APosition in ihrer Zeile nur Leerraum?</summary>
function BlankBefore(const ALines: TArray<string>; const APosition: TTextPosition): Boolean;
/// <summary>Steht hinter APosition in ihrer Zeile nur Leerraum oder ein //-Kommentar?</summary>
function BlankAfter(const ALines: TArray<string>; const APosition: TTextPosition): Boolean;
/// <summary>"A", "A und B", "A, B und C".</summary>
function JoinedList(const AItems: TArray<string>): string;
/// <summary>Name ohne Unit- bzw. Typvorsatz und ohne Typargumente: "A.TB&lt;T&gt;" ergibt "TB".</summary>
function BareName(const AText: string): string;

implementation

uses
  System.SysUtils;

/// <summary>Erstes Token ab AOffset (Index), High + 1 ohne.</summary>
function TokenAtOffset(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  Low, High, Middle: Integer;
begin
  Low := 0;
  High := Length(ATokens);
  while Low < High do
  begin
    Middle := (Low + High) div 2;
    if ATokens[Middle].Offset < AOffset then
    begin
      Low := Middle + 1;
    end
    else
    begin
      High := Middle;
    end;
  end;
  Result := Low;
end;

/// <summary>Steht vor APosition in ihrer Zeile nur Leerraum?</summary>
function BlankBefore(const ALines: TArray<string>; const APosition: TTextPosition): Boolean;
begin
  Result := (APosition.Line < Length(ALines)) and (Trim(Copy(ALines[APosition.Line], 1, APosition.Character)) = '');
end;

/// <summary>Steht hinter APosition in ihrer Zeile nur Leerraum oder ein //-Kommentar?</summary>
function BlankAfter(const ALines: TArray<string>; const APosition: TTextPosition): Boolean;
var
  Rest: string;
begin
  Result := False;
  if APosition.Line >= Length(ALines) then
  begin
    Exit;
  end;
  Rest := Trim(Copy(ALines[APosition.Line], APosition.Character + 1, MaxInt));
  Result := (Rest = '') or Rest.StartsWith('//');
end;

/// <summary>"A", "A und B", "A, B und C".</summary>
function JoinedList(const AItems: TArray<string>): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(AItems) do
  begin
    if Index = 0 then
    begin
      Result := AItems[Index];
    end
    else if Index = High(AItems) then
    begin
      Result := Result + ' und ' + AItems[Index];
    end
    else
    begin
      Result := Result + ', ' + AItems[Index];
    end;
  end;
end;

/// <summary>Name ohne Unit- bzw. Typvorsatz und ohne Typargumente: "A.TB&lt;T&gt;" ergibt "TB".</summary>
function BareName(const AText: string): string;
begin
  Result := Trim(AText);
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
  Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
end;

end.
