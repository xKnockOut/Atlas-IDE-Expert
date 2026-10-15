unit Atlas.Text.Entities;

// XML-Entities entschlüsseln (gemeinsam für Server und Plugin, ADR 0012):
// &lt; &gt; &amp; &quot; &apos; sowie numerische &#NN; und &#xNN;
// (auch über U+FFFF als Surrogatpaar). Unbekanntes bleibt stehen.

interface

type
  TTextEntities = class
  public
    class function Decode(const AText: string): string; static;
    /// <summary>Zeichen zum Codepunkt; '' für 0, Surrogate und Werte über U+10FFFF.</summary>
    class function CodePointText(ACode: Integer): string; static;
  end;

implementation

uses
  System.SysUtils;

{ TTextEntities }

class function TTextEntities.CodePointText(ACode: Integer): string;
begin
  if (ACode <= 0) or (ACode > $10FFFF) or ((ACode >= $D800) and (ACode <= $DFFF)) then
    Exit('');
  if ACode <= $FFFF then
    Exit(Char(ACode));
  Dec(ACode, $10000);
  Result := Char($D800 + (ACode shr 10)) + Char($DC00 + (ACode and $3FF));
end;

class function TTextEntities.Decode(const AText: string): string;
var
  Index, Close, Code: Integer;
  Name, Replacement: string;
  Builder: TStringBuilder;
begin
  if Pos('&', AText) = 0 then
    Exit(AText);
  Builder := TStringBuilder.Create(Length(AText));
  try
    Index := 1;
    while Index <= Length(AText) do
    begin
      if AText[Index] = '&' then
      begin
        Close := Pos(';', AText, Index + 1);
        if (Close > 0) and (Close - Index <= 10) then
        begin
          Name := Copy(AText, Index + 1, Close - Index - 1);
          Replacement := '';
          if Name = 'lt' then
            Replacement := '<'
          else if Name = 'gt' then
            Replacement := '>'
          else if Name = 'amp' then
            Replacement := '&'
          else if Name = 'quot' then
            Replacement := '"'
          else if Name = 'apos' then
            Replacement := ''''
          else if (Length(Name) > 2) and ((Name[2] = 'x') or (Name[2] = 'X')) and (Name[1] = '#') then
          begin
            if TryStrToInt('$' + Copy(Name, 3, MaxInt), Code) then
              Replacement := CodePointText(Code);
          end
          else if (Length(Name) > 1) and (Name[1] = '#') then
          begin
            if TryStrToInt(Copy(Name, 2, MaxInt), Code) then
              Replacement := CodePointText(Code);
          end;
          if Replacement <> '' then
          begin
            Builder.Append(Replacement);
            Index := Close + 1;
            Continue;
          end;
        end;
      end;
      Builder.Append(AText[Index]);
      Inc(Index);
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

end.
