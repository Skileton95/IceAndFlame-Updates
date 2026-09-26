using System.Security.Cryptography;
using System.Text;

if (args.Length != 4 || !string.Equals(args[0], "sign", StringComparison.OrdinalIgnoreCase))
{
    Console.Error.WriteLine("Usage: ManifestSigner sign <private-key.pem> <input.json> <output.sig>");
    return 2;
}

var privateKeyPath = args[1];
var inputPath = args[2];
var outputPath = args[3];

var pem = await File.ReadAllTextAsync(privateKeyPath, Encoding.UTF8);
var data = await File.ReadAllBytesAsync(inputPath);

using var rsa = RSA.Create();
rsa.ImportFromPem(pem);
var signature = rsa.SignData(data, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
await File.WriteAllTextAsync(
    outputPath,
    Convert.ToBase64String(signature),
    new UTF8Encoding(false));

Console.WriteLine(outputPath);
return 0;
