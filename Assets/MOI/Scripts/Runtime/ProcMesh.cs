using System.Collections.Generic;
using UnityEngine;

namespace MOI
{
    /// <summary>Procedural meshes for the blockout. All are centred on the local origin, +Z forward.</summary>
    public static class ProcMesh
    {
        /// <summary>
        /// Section of a cylinder wall seen from inside, centred on +Z. u runs left to right as the
        /// viewer sees it, v runs bottom to top.
        /// </summary>
        public static Mesh CylinderArc(float radius, float y0, float y1, float arcDegrees, int segments)
        {
            var verts = new List<Vector3>();
            var normals = new List<Vector3>();
            var uvs = new List<Vector2>();
            var tris = new List<int>();
            float half = arcDegrees * 0.5f * Mathf.Deg2Rad;
            for (int i = 0; i <= segments; i++)
            {
                float t = i / (float)segments;
                float a = Mathf.Lerp(-half, half, t);
                var dir = new Vector3(Mathf.Sin(a), 0f, Mathf.Cos(a));
                verts.Add(dir * radius + Vector3.up * y0);
                verts.Add(dir * radius + Vector3.up * y1);
                normals.Add(-dir);
                normals.Add(-dir);
                uvs.Add(new Vector2(t, 0f));
                uvs.Add(new Vector2(t, 1f));
            }
            for (int i = 0; i < segments; i++)
            {
                int bl = i * 2, tl = bl + 1, br = bl + 2, tr = bl + 3;
                tris.AddRange(new[] { bl, tl, tr, bl, tr, br });
            }
            return Build("CylinderArc", verts, normals, uvs, tris);
        }

        /// <summary>Flat ring on the XZ plane facing up. v runs across the band (0 inner, 1 outer).</summary>
        public static Mesh Annulus(float innerRadius, float outerRadius, int segments)
        {
            var verts = new List<Vector3>();
            var normals = new List<Vector3>();
            var uvs = new List<Vector2>();
            var tris = new List<int>();
            for (int i = 0; i <= segments; i++)
            {
                float t = i / (float)segments;
                float a = t * Mathf.PI * 2f;
                var dir = new Vector3(Mathf.Cos(a), 0f, Mathf.Sin(a));
                verts.Add(dir * innerRadius);
                verts.Add(dir * outerRadius);
                normals.Add(Vector3.up);
                normals.Add(Vector3.up);
                uvs.Add(new Vector2(t, 0f));
                uvs.Add(new Vector2(t, 1f));
            }
            for (int i = 0; i < segments; i++)
            {
                int a0 = i * 2, b0 = a0 + 1, a1 = a0 + 2, b1 = a0 + 3;
                tris.AddRange(new[] { a0, a1, b1, a0, b1, b0 });
            }
            return Build("Annulus", verts, normals, uvs, tris);
        }

        /// <summary>Upright cylinder seen from outside, base at y0. Optional flat cap on top.</summary>
        public static Mesh Cylinder(float radius, float y0, float y1, int segments, bool capTop)
        {
            var verts = new List<Vector3>();
            var normals = new List<Vector3>();
            var uvs = new List<Vector2>();
            var tris = new List<int>();
            for (int i = 0; i <= segments; i++)
            {
                float t = i / (float)segments;
                float a = t * Mathf.PI * 2f;
                var dir = new Vector3(Mathf.Cos(a), 0f, Mathf.Sin(a));
                verts.Add(dir * radius + Vector3.up * y0);
                verts.Add(dir * radius + Vector3.up * y1);
                normals.Add(dir);
                normals.Add(dir);
                uvs.Add(new Vector2(t, 0f));
                uvs.Add(new Vector2(t, 1f));
            }
            for (int i = 0; i < segments; i++)
            {
                int b0 = i * 2, t0 = b0 + 1, b1 = b0 + 2, t1 = b0 + 3;
                tris.AddRange(new[] { b0, t0, t1, b0, t1, b1 });
            }
            if (capTop)
            {
                int centre = verts.Count;
                verts.Add(Vector3.up * y1);
                normals.Add(Vector3.up);
                uvs.Add(new Vector2(0.5f, 0.5f));
                for (int i = 0; i <= segments; i++)
                {
                    float a = i / (float)segments * Mathf.PI * 2f;
                    verts.Add(new Vector3(Mathf.Cos(a) * radius, y1, Mathf.Sin(a) * radius));
                    normals.Add(Vector3.up);
                    uvs.Add(new Vector2(Mathf.Cos(a) * 0.5f + 0.5f, Mathf.Sin(a) * 0.5f + 0.5f));
                }
                for (int i = 0; i < segments; i++)
                    tris.AddRange(new[] { centre, centre + 2 + i, centre + 1 + i });
            }
            return Build("Cylinder", verts, normals, uvs, tris);
        }

        public static Mesh Disc(float radius, int segments)
        {
            return Annulus(0f, radius, segments);
        }

        /// <summary>
        /// Elongated hexagonal gem, about 1.1 units tall, long point up. Vertices are split per face so
        /// the shader gets flat facet normals.
        /// </summary>
        public static Mesh Crystal()
        {
            const int sides = 6;
            var top = new Vector3(0f, 0.62f, 0f);
            var bottom = new Vector3(0f, -0.5f, 0f);
            var upper = new Vector3[sides];
            var lower = new Vector3[sides];
            for (int i = 0; i < sides; i++)
            {
                float au = i * Mathf.PI * 2f / sides;
                float al = au + Mathf.PI / sides;
                upper[i] = new Vector3(Mathf.Cos(au) * 0.2f, 0.2f, Mathf.Sin(au) * 0.2f);
                lower[i] = new Vector3(Mathf.Cos(al) * 0.17f, -0.16f, Mathf.Sin(al) * 0.17f);
            }

            var verts = new List<Vector3>();
            var normals = new List<Vector3>();
            var uvs = new List<Vector2>();
            var tris = new List<int>();
            for (int i = 0; i < sides; i++)
            {
                int j = (i + 1) % sides;
                AddFace(verts, normals, uvs, tris, top, upper[i], upper[j]);
                AddFace(verts, normals, uvs, tris, upper[i], lower[i], upper[j]);
                AddFace(verts, normals, uvs, tris, upper[j], lower[i], lower[j]);
                AddFace(verts, normals, uvs, tris, bottom, lower[j], lower[i]);
            }
            return Build("Crystal", verts, normals, uvs, tris);
        }

        // The gem is convex around the origin, so "outward" is simply "away from the origin".
        static void AddFace(List<Vector3> verts, List<Vector3> normals, List<Vector2> uvs, List<int> tris,
            Vector3 a, Vector3 b, Vector3 c)
        {
            var n = Vector3.Cross(b - a, c - a).normalized;
            if (Vector3.Dot(n, (a + b + c) / 3f) < 0f)
            {
                var tmp = b; b = c; c = tmp;
                n = -n;
            }
            int start = verts.Count;
            verts.Add(a); verts.Add(b); verts.Add(c);
            normals.Add(n); normals.Add(n); normals.Add(n);
            uvs.Add(new Vector2(0f, 0f)); uvs.Add(new Vector2(1f, 0f)); uvs.Add(new Vector2(0.5f, 1f));
            tris.Add(start); tris.Add(start + 1); tris.Add(start + 2);
        }

        static Mesh Build(string name, List<Vector3> verts, List<Vector3> normals, List<Vector2> uvs, List<int> tris)
        {
            var mesh = new Mesh { name = name };
            mesh.SetVertices(verts);
            mesh.SetNormals(normals);
            mesh.SetUVs(0, uvs);
            mesh.SetTriangles(tris, 0);
            mesh.RecalculateBounds();
            return mesh;
        }
    }
}
