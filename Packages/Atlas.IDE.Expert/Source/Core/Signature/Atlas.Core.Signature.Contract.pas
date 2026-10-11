unit Atlas.Core.Signature.Contract;

// Daten des Parameter-Hints (#436): Signaturen eines Aufrufs mit der Lage der
// Parameter im Text, aktiver Signatur und aktivem Parameter, wie sie der
// Server über textDocument/signatureHelp liefert (#32).

interface

uses
  System.SysUtils;

type
  TAtlasSignatureParameter = record
    /// <summary>Lage im Label der Signatur, 0-basiert, Stop exklusiv; -1 wenn unbekannt.</summary>
    Start: Integer;
    Stop: Integer;
    /// <summary>Doku des Parameters aus XMLDoc; '' ohne.</summary>
    Documentation: string;
    /// <summary>Text des Parameters im Label.</summary>
    function Text(const ALabel: string): string;
  end;

  TAtlasSignature = record
    /// <summary>Ganze Signatur, z. B. "function Format(const Format: string; const Args: array of const): string".</summary>
    Label_: string;
    Documentation: string;
    Parameters: TArray<TAtlasSignatureParameter>;
  end;

  TAtlasSignatureHelp = record
    Signatures: TArray<TAtlasSignature>;
    /// <summary>Vom Server gewählte Signatur bzw. -1.</summary>
    ActiveSignature: Integer;
    /// <summary>Vom Server ermittelter Parameter bzw. -1.</summary>
    ActiveParameter: Integer;
    function IsEmpty: Boolean;
  end;

implementation

{ TAtlasSignatureParameter }

function TAtlasSignatureParameter.Text(const ALabel: string): string;
begin
  if (Start >= 0) and (Stop > Start) then
    Result := Copy(ALabel, Start + 1, Stop - Start)
  else
    Result := '';
end;

{ TAtlasSignatureHelp }

function TAtlasSignatureHelp.IsEmpty: Boolean;
begin
  Result := Length(Signatures) = 0;
end;

end.
