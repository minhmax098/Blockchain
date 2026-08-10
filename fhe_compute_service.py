import random
import pandas as pd
import numpy as np
from faker import Faker
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.model_selection import train_test_split
from concrete.ml.sklearn import LogisticRegression
import time

# Initialize Faker
fake = Faker()

# Define DNA nucleotides
nucleotides = ['A', 'T', 'C', 'G']

# Function to generate a random DNA sequence of a given length
def generate_dna_sequence(length):
    return ''.join(random.choices(nucleotides, k=length))

# Create a synthetic dataset
def create_synthetic_dataset(n_samples=1000):
    data = []
    for _ in range(n_samples):
        sample_id = fake.uuid4()
        sequence_length = random.randint(50, 150)
        sequence = generate_dna_sequence(sequence_length)
        chromosome = random.choice(list(range(1, 23)) + ['X', 'Y'])
        region_type = random.choice(['coding', 'non-coding'])

        # Simulate ancestry based on some random logic or keep it entirely random
        ancestry = random.choice(['African', 'European', 'Asian', 'Native American', 'Oceanian'])

        # We simulate phenotype (binary classification) based on some simple hidden rule
        # This gives the logistic regression something to learn
        # E.g., if sequence_length > 100 and ancestry is 'European', high chance of phenotype 1
        phenotype_prob = 0.5
        if sequence_length > 100:
            phenotype_prob += 0.2
        if ancestry == 'European':
            phenotype_prob += 0.1

        phenotype = np.random.binomial(1, min(max(phenotype_prob, 0), 1))

        # Introduce a specific gene variant for realistic screening queries
        variant_brca1 = random.choice([0, 1])

        data.append([
            sample_id, sequence, sequence_length, chromosome,
            region_type, ancestry, variant_brca1, phenotype
        ])

    columns = [
        'sample_id', 'sequence', 'sequence_length', 'chromosome',
        'region_type', 'ancestry', 'variant_brca1', 'phenotype'
    ]
    return pd.DataFrame(data, columns=columns)

def run_fhe_pipeline():
    print("Generating synthetic genomic dataset...")
    df = create_synthetic_dataset(n_samples=500)

    print("Preprocessing data...")
    # Encode categorical columns
    label_encoders = {}
    for column in ['chromosome', 'region_type', 'ancestry']:
        le = LabelEncoder()
        df[column] = df[column].astype(str)
        df[column] = le.fit_transform(df[column])
        label_encoders[column] = le

    # Features: sequence_length, chromosome, region_type, ancestry, variant_brca1
    X = df[['sequence_length', 'chromosome', 'region_type', 'ancestry', 'variant_brca1']].values
    y = df['phenotype'].values

    # Split the data
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

    # Scale the features
    scaler = StandardScaler()
    X_train = scaler.fit_transform(X_train)
    X_test = scaler.transform(X_test)

    # Train a model in the clear
    print("Training Logistic Regression model...")
    model = LogisticRegression(n_bits=8)
    model.fit(X_train, y_train)

    # Compile for FHE
    print("Compiling model for FHE...")
    model.compile(X_train)

    # Simulate an inference request (e.g. from the buyer)
    print("Simulating homomorphic computation (Limited Access)...")

    # Let's take a single batch (e.g., 5 patients)
    sample_batch = X_test[:5]

    # Predict in the clear
    y_pred_clear = model.predict(sample_batch)

    # Predict over FHE (the data would ideally come from IPFS ciphertext here)
    start_time = time.time()
    y_pred_fhe = model.predict(sample_batch, fhe="execute")
    fhe_time = time.time() - start_time

    print("="*40)
    print("FHE Computation Results")
    print("="*40)
    print(f"In clear predictions : {y_pred_clear}")
    print(f"FHE predictions      : {y_pred_fhe}")
    print(f"Execution time (s)   : {fhe_time:.2f}")

    # Check if they match
    match = np.array_equal(y_pred_clear, y_pred_fhe)
    print(f"Predictions match    : {match}")
    print("="*40)

    print("\nNote: In the full system, this script would:")
    print("1. Listen for LimitedAccessGranted events on the GDMNFT Smart Contract.")
    print("2. Retrieve the FHE-encrypted data (CID_fhe) from IPFS for the specific Patient/SGD NFT.")
    print("3. Execute the homomorphic operation using model.predict(..., fhe='execute').")
    print("4. Forward the FHE result back to the buyer.")
    print("5. Trigger an Oracle to call updateOperationsBalance(...) on-chain.")

if __name__ == "__main__":
    run_fhe_pipeline()
