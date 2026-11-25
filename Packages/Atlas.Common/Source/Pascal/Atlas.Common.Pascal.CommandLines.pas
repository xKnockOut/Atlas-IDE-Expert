unit Atlas.Common.Pascal.CommandLines;

// Befehlszeilen im Quelltext (#293): "/name Argumente" zerlegen und prüfen, ob
// eine Zeile im Code steht (nicht in Kommentar, String oder asm). Welche Befehle
// es gibt und was sie tun, weiß Editing.SlashCommands.

interface

uses
  Atlas.Common.Pascal.Contract;

type
  TPascalCommandLines = class
  public
    /// <summary>Ist ALine ein Befehl "/name Argumente"? Ohne Prüfung, ob der Name bekannt ist.</summary>
    class function Split(const ALine: string; out AName, AArguments: string): Boolean; static;
    /// <summary>Steht Zeile ALine im Code (nicht in Kommentar, String oder asm)?</summary>
    class function IsCodeLine(const ATokens: TArray<TPascalToken>; ALine: Integer): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

{ TPascalCommandLines }

class function TPascalCommandLines.Split(const ALine: string; out AName, AArguments: string): Boolean;
var
  mText: string;
  mIndex: Integer;
begin
  AName := '';
  AArguments := '';
  mText := Trim(ALine);
  // "/name": Buchstabe direkt nach "/"; "//" ist ein Kommentar.
  if (Length(mText) < 2) or (mText[1] <> '/') or not CharInSet(mText[2], ['A'..'Z', 'a'..'z']) then
  begin
    Exit(False);
  end;
  mIndex := 2;
  while (mIndex <= Length(mText)) and CharInSet(mText[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '_', '!', '-']) do
  begin
    Inc(mIndex);
  end;
  if (mIndex <= Length(mText)) and (mText[mIndex] <> ' ') then
  begin
    Exit(False);
  end;
  AName := Copy(mText, 2, mIndex - 2);
  AArguments := Trim(Copy(mText, mIndex, MaxInt));
  Result := True;
end;

class function TPascalCommandLines.IsCodeLine(const ATokens: TArray<TPascalToken>; ALine: Integer): Boolean;
var
  mToken: TPascalToken;
  mInAsm: Boolean;
begin
  mInAsm := False;
  for mToken in ATokens do
  begin
    if mToken.StartPos.Line > ALine then
    begin
      Break;
    end;
    // Mehrzeiliger Kommentar oder String über der Zeile.
    if (mToken.StartPos.Line < ALine) and (mToken.EndPos.Line >= ALine) and
      (mToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.StringLiteral]) then
    begin
      Exit(False);
    end;
    if mToken.StartPos.Line < ALine then
    begin
      if mToken.IsKeyword('asm') then
      begin
        mInAsm := True;
      end
      else if mInAsm and mToken.IsKeyword('end') then
      begin
        mInAsm := False;
      end;
    end;
  end;
  Result := not mInAsm;
end;

end.
