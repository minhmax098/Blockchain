import unittest
import numpy as np
from fhe_compute_service import (
    PRISMEngine,
    Ciphertext,
    encode_genotype_to_bits,
    generate_synthetic_vcf_dataset,
    run_prism_fhe_limited_access
)

class TestPRISMFHEEngine(unittest.TestCase):

    def setUp(self):
        self.engine = PRISMEngine(block_size=10, plain_modulus=7340033)

    def test_encode_genotype_to_bits(self):
        self.assertEqual(encode_genotype_to_bits('0/0'), (0, 0))
        self.assertEqual(encode_genotype_to_bits('0/1'), (0, 1))
        self.assertEqual(encode_genotype_to_bits('1/0'), (1, 0))
        self.assertEqual(encode_genotype_to_bits('1/1'), (1, 1))

    def test_eval_add_sub_mult(self):
        ct1 = self.engine.encrypt([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        ct2 = self.engine.encrypt([10, 9, 8, 7, 6, 5, 4, 3, 2, 1])

        add_res = self.engine.decrypt(self.engine.eval_add(ct1, ct2))
        self.assertEqual(add_res, [11] * 10)

        sub_res = self.engine.decrypt(self.engine.eval_sub(ct2, ct1))
        self.assertEqual(sub_res, [9, 7, 5, 3, 1, 7340032, 7340030, 7340028, 7340026, 7340024])

        mult_ct = self.engine.eval_mult(ct1, ct2)
        mult_res = self.engine.decrypt(mult_ct)
        self.assertEqual(mult_res, [10, 18, 24, 28, 30, 30, 28, 24, 18, 10])
        self.assertEqual(mult_ct.depth, 1)

    def test_recessive_dominant_filtering_add_in(self):
        dataset = generate_synthetic_vcf_dataset(num_samples=4, num_variants=50)
        res = run_prism_fhe_limited_access(dataset=dataset, inheritance_model="recessive_dominant")

        self.assertTrue(res["verification_passed"])
        self.assertLessEqual(res["multiplicative_depth"], 2)

    def test_de_novo_filtering_add_in(self):
        dataset = generate_synthetic_vcf_dataset(num_samples=4, num_variants=50)
        res = run_prism_fhe_limited_access(dataset=dataset, inheritance_model="de_novo")

        self.assertTrue(res["verification_passed"])
        self.assertLessEqual(res["multiplicative_depth"], 2)


if __name__ == "__main__":
    unittest.main()
