unit Setup.Core.License;

// Lizenzvereinbarung (EULA) im Installer: Der Text liegt als EULA.txt im
// Paket neben dem Installer und wird mit installiert. Die Zustimmung merkt
// sich der Installer als Fingerabdruck (SHA-256) des Texts unter
// Software\Atlas\Setup; eine Aktualisierung fragt nur wieder, wenn sich der
// Text geändert hat oder Atlas zwischendurch entfernt wurde.
// Ohne Windows und VCL.

interface

uses
  Setup.Core.Contract;

type
  TSetupLicense = class
  public const
    FileName = 'EULA.txt';
    AcceptedValue = 'LicenseAccepted';
  public
    /// <summary>Ohne BOM, Zeilenumbrüche als CRLF, ohne Leerraum am Ende.</summary>
    class function Normalize(const AText: string): string; static;
    /// <summary>SHA-256 des normalisierten Texts als Hexadezimalzahl.</summary>
    class function Fingerprint(const AText: string): string; static;
    /// <summary>False ohne Text; sonst True, solange diesem Text nicht zugestimmt wurde.</summary>
    class function NeedsAcceptance(const ASystem: ISetupSystem; const AText: string): Boolean; static;
    /// <summary>Merkt die Zustimmung zu AText.</summary>
    class procedure Accept(const ASystem: ISetupSystem; const AText: string); static;
  end;

implementation

uses
  System.SysUtils,
  System.Hash,
  Setup.Core.Installer;

{ TSetupLicense }

class function TSetupLicense.Normalize(const AText: string): string;
begin
  Result := AText;
  if (Result <> '') and (Result[1] = #$FEFF) then
    Delete(Result, 1, 1);
  Result := StringReplace(Result, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
  Result := TrimRight(Result);
  Result := StringReplace(Result, #10, #13#10, [rfReplaceAll]);
end;

class function TSetupLicense.Fingerprint(const AText: string): string;
begin
  Result := THashSHA2.GetHashString(Normalize(AText));
end;

class function TSetupLicense.NeedsAcceptance(const ASystem: ISetupSystem; const AText: string): Boolean;
begin
  Result := False;
  if Normalize(AText) = '' then
    Exit;
  Result := not SameText(ASystem.ReadString(TSetupInstaller.SetupKey, AcceptedValue), Fingerprint(AText));
end;

class procedure TSetupLicense.Accept(const ASystem: ISetupSystem; const AText: string);
begin
  ASystem.WriteString(TSetupInstaller.SetupKey, AcceptedValue, Fingerprint(AText));
end;

end.
