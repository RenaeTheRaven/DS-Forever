using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;

namespace DsfDesktop
{
    /// <summary>
    /// custom-thor: a self-signed RSA TLS server certificate written out by hand (DER), for runtimes without CertificateRequest
    /// (Mono, which is what Wine/Proton runs Desktop on; the tests use it). The same fields BridgeCert asks CertificateRequest for:
    /// CN, not a CA, digitalSignature + keyEncipherment, server authentication, SHA-256 with RSA.
    /// </summary>
    public static class SelfSigned
    {
        /// <summary>the certificate (DER) for [rsa]'s key</summary>
        public static byte[] Der(string commonName, RSA rsa, DateTime notBeforeUtc, DateTime notAfterUtc)
        {
            var pub = rsa.ExportParameters(false);
            var sigAlg = Seq(Oid("1.2.840.113549.1.1.11"), Null());
            var name = Seq(Set(Seq(Oid("2.5.4.3"), Tlv(0x0C, Encoding.UTF8.GetBytes(commonName ?? "")))));
            var spki = Seq(Seq(Oid("1.2.840.113549.1.1.1"), Null()), BitString(Seq(Int(pub.Modulus), Int(pub.Exponent))));
            var serial = new byte[8];
            using (var rng = RandomNumberGenerator.Create()) rng.GetBytes(serial);
            serial[0] = (byte)((serial[0] & 0x7F) | 0x01);
            var extensions = Seq(
                Seq(Oid("2.5.29.19"), Tlv(0x04, Seq())),                                        // basicConstraints: not a CA
                Seq(Oid("2.5.29.15"), Tlv(0x04, Tlv(0x03, new byte[] { 0x05, 0xA0 }))),         // keyUsage: digitalSignature, keyEncipherment
                Seq(Oid("2.5.29.37"), Tlv(0x04, Seq(Oid("1.3.6.1.5.5.7.3.1")))));               // extKeyUsage: serverAuth
            var tbs = Seq(
                Tlv(0xA0, Int(new byte[] { 2 })),                                               // v3
                Int(serial), sigAlg, name,
                Seq(Time(notBeforeUtc), Time(notAfterUtc)),
                name, spki,
                Tlv(0xA3, extensions));
            var sig = rsa.SignData(tbs, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
            return Seq(tbs, sigAlg, BitString(sig));
        }

        // ---- DER

        static byte[] Tlv(int tag, params byte[][] parts)
        {
            int n = parts.Sum(p => p.Length);
            var res = new List<byte>(n + 6) { (byte)tag };
            if (n < 0x80) res.Add((byte)n);
            else
            {
                var len = new List<byte>();
                for (int v = n; v > 0; v >>= 8) len.Insert(0, (byte)(v & 0xFF));
                res.Add((byte)(0x80 | len.Count));
                res.AddRange(len);
            }
            foreach (var p in parts) res.AddRange(p);
            return res.ToArray();
        }

        static byte[] Seq(params byte[][] parts) => Tlv(0x30, parts);
        static byte[] Set(params byte[][] parts) => Tlv(0x31, parts);
        static byte[] Null() => new byte[] { 0x05, 0x00 };
        static byte[] BitString(byte[] b) => Tlv(0x03, new byte[] { 0 }, b);

        /// <summary>a non-negative big-endian integer</summary>
        static byte[] Int(byte[] bigEndian)
        {
            int skip = 0;
            while (skip < bigEndian.Length - 1 && bigEndian[skip] == 0) skip++;
            var v = bigEndian.Skip(skip).ToArray();
            return (v[0] & 0x80) != 0 ? Tlv(0x02, new byte[] { 0 }, v) : Tlv(0x02, v);
        }

        static byte[] Oid(string dotted)
        {
            var n = dotted.Split('.').Select(long.Parse).ToArray();
            var b = new List<byte> { (byte)(n[0] * 40 + n[1]) };
            foreach (var v in n.Skip(2))
            {
                var part = new List<byte> { (byte)(v & 0x7F) };
                for (long r = v >> 7; r > 0; r >>= 7) part.Insert(0, (byte)(0x80 | (r & 0x7F)));
                b.AddRange(part);
            }
            return Tlv(0x06, b.ToArray());
        }

        /// <summary>UTCTime up to 2049, GeneralizedTime after (RFC 5280)</summary>
        static byte[] Time(DateTime utc) => utc.Year < 2050
            ? Tlv(0x17, Encoding.ASCII.GetBytes(utc.ToString("yyMMddHHmmss") + "Z"))
            : Tlv(0x18, Encoding.ASCII.GetBytes(utc.ToString("yyyyMMddHHmmss") + "Z"));
    }
}
